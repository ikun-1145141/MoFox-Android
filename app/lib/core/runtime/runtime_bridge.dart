import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/domain/system_stats.dart';

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
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'runInstallTask',
      <String, Object>{'task': task, 'args': args},
    );
    return RuntimeTaskResult.fromMap(result ?? const <Object?, Object?>{});
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
  /// - napcat：留空，napcat 是全局唯一安装。
  Future<void> startProcess(
    String name, {
    Map<String, String> args = const <String, String>{},
  }) =>
      _channel.invokeMethod<void>(
        'startProcess',
        <String, Object>{'name': name, 'args': args},
      );

  Future<void> stopProcess(String name) => _channel.invokeMethod<void>(
        'stopProcess',
        <String, Object>{'name': name},
      );

  Future<void> restartProcess(
    String name, {
    Map<String, String> args = const <String, String>{},
  }) =>
      _channel.invokeMethod<void>(
        'restartProcess',
        <String, Object>{'name': name, 'args': args},
      );

  /// 拉一份当前各托管进程的状态快照。
  Future<Map<String, String>> processStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('processStatus');
    return result?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
        const <String, String>{};
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
    final id = await _channel.invokeMethod<String>(
      'openShell',
      <String, Object>{'cwd': cwd},
    );
    return id ?? '';
  }

  Future<void> writeShell(String sessionId, String data) =>
      _channel.invokeMethod<void>('writeShell', <String, Object>{
        'sessionId': sessionId,
        'data': data,
      });

  /// 调整 native PTY 尺寸，给 nano/top 这类全屏程序同步窗口大小。
  Future<void> resizeShell(String sessionId, int cols, int rows) =>
      _channel.invokeMethod<void>('resizeShell', <String, Object>{
        'sessionId': sessionId,
        'cols': cols,
        'rows': rows,
      });

  Future<void> closeShell(String sessionId) => _channel.invokeMethod<void>(
        'closeShell',
        <String, Object>{'sessionId': sessionId},
      );
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

String _cleanInstallLogLine(String line) {
  return line
      .replaceAll(_ansiEscapePattern, '')
      .replaceAll(_controlCharsPattern, '')
      .trimRight();
}

final RegExp _ansiEscapePattern = RegExp(
  '[\x1B\x9B](?:[@-Z\\-_]|\\[[0-?]*[ -/]*[@-~]|\\][^\x07]*(?:\x07|\x1B\\\\))',
);

final RegExp _controlCharsPattern = RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
