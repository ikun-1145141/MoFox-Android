import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/domain/system_stats.dart';
import '../utils/app_logger.dart';

/// 与原生 `RuntimeBridgePlugin` 对话的方法通道单例。
///
/// 通道协议见 `android/app/src/main/kotlin/.../runtime/RuntimeBridgePlugin.kt`。
class RuntimeBridge {
  RuntimeBridge._();

  static const MethodChannel _channel = MethodChannel('mofox/runtime');
  static const EventChannel _events = EventChannel('mofox/runtime/events');

  /// rootfs 是否已解压完成。
  Future<bool> isBootstrapped() async {
    final result = await _channel.invokeMethod<bool>('isBootstrapped');
    return result ?? false;
  }

  /// 解压内嵌 bootstrap zip 到 `filesDir/usr`。
  ///
  /// 返回流向上抛 0..1 的进度（0 = 校验, 1 = 完成）。
  Stream<double> installBootstrap() {
    return _events
        .receiveBroadcastStream(<String, Object?>{'topic': 'bootstrap'})
        .where(_isBootstrapEvent)
        .map((event) => (event as Map<Object?, Object?>)['payload'])
        .where((value) => value is num)
        .cast<num>()
        .map((value) => value.toDouble());
  }

  /// 执行一次安装任务并返回日志/二维码等结果。
  Future<RuntimeTaskResult> runInstallTask(
    String task, {
    Map<String, String> args = const <String, String>{},
  }) async {
    appLogger.i('runtime: runInstallTask "$task" args=${args.keys.toList()}');
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'runInstallTask',
        <String, Object>{'task': task, 'args': args},
      );
      final parsed =
          RuntimeTaskResult.fromMap(result ?? const <Object?, Object?>{});
      appLogger.i(
          'runtime: runInstallTask "$task" success=${parsed.success} logs=${parsed.logs.length}');
      return parsed;
    } on PlatformException catch (e) {
      appLogger.e(
          'runtime: runInstallTask "$task" PlatformException code=${e.code} msg=${e.message}',
          error: e);
      rethrow;
    } catch (e, s) {
      appLogger.e('runtime: runInstallTask "$task" error',
          error: e, stackTrace: s);
      rethrow;
    }
  }

  /// 原生安装任务实时日志（按 task 过滤）。
  Stream<String> installTaskLogs(String task) {
    return installEvents()
        .where((event) => event.task == task)
        .map((event) => event.line);
  }

  /// 原生安装事件流（不区分 task）。每个事件包含 task 名与一行日志。
  ///
  /// Wizard 应在整个安装流程开始时订阅一次，按事件中的 [InstallEvent.task] 自行分发，
  /// 安装结束（成功/失败）再 cancel。这样可以避免在 task 切换瞬间 sink 被 detach
  /// 导致原生端 emit 的事件被丢掉。
  Stream<InstallEvent> installEvents() {
    return _events
        .receiveBroadcastStream(<String, Object?>{'topic': 'install'})
        .where(
          (event) =>
              event is Map<Object?, Object?> && event['topic'] == 'install',
        )
        .map((event) => (event as Map<Object?, Object?>)['payload'])
        .where((payload) => payload is Map<Object?, Object?>)
        .cast<Map<Object?, Object?>>()
        .map((payload) {
          final task = payload['task']?.toString() ?? '';
          final line = _cleanInstallLogLine(payload['line']?.toString() ?? '');
          return InstallEvent(task: task, line: line);
        })
        .where((event) => event.task.isNotEmpty && event.line.isNotEmpty);
  }

  /// 启动 / 停止 / 重启托管进程。`name` ∈ {bot, napcat}.
  ///
  /// `args` 给原生端 `processScript` 取参数：
  /// - bot：`repoPath`（实例的 Neo-MoFox 路径）、`instanceId`（脚本文件名后缀，避免多实例覆盖）。
  /// - napcat：`botQq`（NapCat 登录/启动使用的 QQ 号），NapCat 是全局唯一安装。
  Future<void> startProcess(
    String name, {
    Map<String, String> args = const <String, String>{},
  }) {
    appLogger.i('runtime: startProcess "$name" args=${args.keys.toList()}');
    return _channel.invokeMethod<void>(
      'startProcess',
      <String, Object>{'name': name, 'args': args},
    );
  }

  Future<void> stopProcess(String name) {
    appLogger.i('runtime: stopProcess "$name"');
    return _channel.invokeMethod<void>(
      'stopProcess',
      <String, Object>{'name': name},
    );
  }

  Future<void> restartProcess(
    String name, {
    Map<String, String> args = const <String, String>{},
  }) {
    appLogger.i('runtime: restartProcess "$name" args=${args.keys.toList()}');
    return _channel.invokeMethod<void>(
      'restartProcess',
      <String, Object>{'name': name, 'args': args},
    );
  }

  /// 拉一份当前各托管进程的状态快照。
  Future<Map<String, String>> processStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('processStatus');
    return result?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
        const <String, String>{};
  }

  /// 托管进程实时日志流。`name` 为 `bot` 或 `napcat`。
  Stream<ProcessEvent> processEvents() {
    return _events
        .receiveBroadcastStream(<String, Object?>{'topic': 'process'})
        .where(
          (event) =>
              event is Map<Object?, Object?> && event['topic'] == 'process',
        )
        .map((event) => (event as Map<Object?, Object?>)['payload'])
        .where((payload) => payload is Map<Object?, Object?>)
        .cast<Map<Object?, Object?>>()
        .map((payload) {
          final name = payload['name']?.toString() ?? '';
          final line = _cleanInstallLogLine(payload['line']?.toString() ?? '');
          return ProcessEvent(name: name, line: line);
        })
        .where((event) => event.name.isNotEmpty && event.line.isNotEmpty);
  }

  /// 拉一份 Android 设备和运行负载快照。
  Future<SystemStats> systemStats() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('systemStats');
    return SystemStats.fromMap(result ?? const <Object?, Object?>{});
  }

  /// 终端 stdout 流，按 `sessionId` 过滤。
  ///
  /// 原生端 `RuntimeBridgePlugin.openShell` 起一个 ProcessBuilder + login_ubuntu 的
  /// 交互式 bash，stdout 切片后通过 EventChannel 抛过来。订阅之前先 `openShell`
  /// 拿到 sessionId。
  Stream<String> shellOutput(String sessionId) {
    return _events
        .receiveBroadcastStream(<String, Object?>{
          'topic': 'pty',
          'sessionId': sessionId,
        })
        .where(
          (event) => event is Map<Object?, Object?> && event['topic'] == 'pty',
        )
        .map((event) => (event as Map<Object?, Object?>)['payload'])
        .where((payload) => payload is Map<Object?, Object?>)
        .cast<Map<Object?, Object?>>()
        .where((payload) => payload['sessionId']?.toString() == sessionId)
        .map((payload) => payload['data']?.toString() ?? '');
  }

  /// 起一个交互式 shell，`cwd` 是进 Debian 后的工作目录。
  ///
  /// 三种入口：
  /// - dashboard 顶部「打开终端」→ `cwd = /root`
  /// - 实例卡片「在 bot 目录开终端」→ `cwd = instance.repoPath`
  /// - 实例卡片「在 instance 根目录开终端」→ `cwd = instance.installDir`
  Future<String> openShell({String cwd = '/root'}) async {
    appLogger.i('runtime: openShell cwd="$cwd"');
    try {
      final id = await _channel.invokeMethod<String>(
        'openShell',
        <String, Object>{'cwd': cwd},
      );
      appLogger.d('runtime: openShell -> sessionId=$id');
      return id ?? '';
    } on PlatformException catch (e) {
      appLogger.e(
          'runtime: openShell PlatformException code=${e.code} msg=${e.message}',
          error: e);
      rethrow;
    }
  }

  Future<void> writeShell(String sessionId, String data) {
    return _channel.invokeMethod<void>('writeShell', <String, Object>{
      'sessionId': sessionId,
      'data': data,
    });
  }

  /// 调整 native PTY 尺寸，给 nano/top 这类全屏程序同步窗口大小。
  Future<void> resizeShell(String sessionId, int cols, int rows) =>
      _channel.invokeMethod<void>('resizeShell', <String, Object>{
        'sessionId': sessionId,
        'cols': cols,
        'rows': rows,
      });

  Future<void> closeShell(String sessionId) {
    appLogger.i('runtime: closeShell sessionId="$sessionId"');
    return _channel.invokeMethod<void>(
      'closeShell',
      <String, Object>{'sessionId': sessionId},
    );
  }

  /// 读取 rootfs 内的文件内容（文本）。文件不存在返回空字符串。
  Future<String> readFile(String rootfsPath) async {
    final result =
        await _channel.invokeMethod<String>('readFile', <String, Object>{
      'path': rootfsPath,
    });
    return result ?? '';
  }

  /// 检查 rootfs 内文件是否存在。
  Future<bool> fileExists(String rootfsPath) async {
    final result =
        await _channel.invokeMethod<bool>('fileExists', <String, Object>{
      'path': rootfsPath,
    });
    return result ?? false;
  }

  /// 列出 rootfs 内目录内容。返回 [{name, isDir, size}] 列表。
  Future<List<RootfsEntry>> listDir(String rootfsPath) async {
    final result =
        await _channel.invokeMethod<List<Object?>>('listDir', <String, Object>{
      'path': rootfsPath,
    });
    if (result == null) return const <RootfsEntry>[];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(RootfsEntry.fromMap)
        .toList(growable: false);
  }

  /// 在 rootfs 内用 tar 打包指定路径到 destPath（rootfs 内绝对路径）。
  /// 返回 host 层文件绝对路径。
  Future<String> packToTar({
    required List<String> paths,
    required String destPath,
  }) async {
    final result =
        await _channel.invokeMethod<String>('packToTar', <String, Object>{
      'paths': paths,
      'dest': destPath,
    });
    return result ?? '';
  }
}

bool _isBootstrapEvent(Object? event) {
  return event is Map<Object?, Object?> && event['topic'] == 'bootstrap';
}

class RuntimeTaskResult {
  const RuntimeTaskResult({
    required this.success,
    required this.logs,
    this.qrPayload,
    this.error,
  });

  final bool success;
  final List<String> logs;
  final String? qrPayload;
  final String? error;

  factory RuntimeTaskResult.fromMap(Map<Object?, Object?> map) {
    final rawLogs = map['logs'];
    return RuntimeTaskResult(
      success: map['success'] == true,
      logs: rawLogs is List<Object?>
          ? rawLogs
              .map((line) => _cleanInstallLogLine(line.toString()))
              .toList()
          : const <String>[],
      qrPayload: map['qrPayload']?.toString(),
      error: map['error']?.toString(),
    );
  }
}

final runtimeBridgeProvider = Provider<RuntimeBridge>((_) => RuntimeBridge._());

class InstallEvent {
  const InstallEvent({required this.task, required this.line});

  final String task;
  final String line;
}

class ProcessEvent {
  const ProcessEvent({required this.name, required this.line});

  final String name;
  final String line;
}

String _cleanInstallLogLine(String line) {
  // 保留 ANSI 颜色转义码（ESC 0x1B + [），前端用 AnsiColorText 渲染。
  // 只剥除其他控制字符（排除 0x1B）。
  return line.replaceAll(_controlCharsPattern, '').trimRight();
}

final RegExp _controlCharsPattern =
    RegExp('[\x00-\x08\x0B\x0C\x0E-\x1A\x1C-\x1F\x7F]');

class RootfsEntry {
  const RootfsEntry({
    required this.name,
    required this.isDir,
    required this.size,
  });

  final String name;
  final bool isDir;
  final int size;

  factory RootfsEntry.fromMap(Map<Object?, Object?> map) {
    return RootfsEntry(
      name: map['name']?.toString() ?? '',
      isDir: map['isDir'] == true,
      size: (map['size'] as num?)?.toInt() ?? 0,
    );
  }
}
