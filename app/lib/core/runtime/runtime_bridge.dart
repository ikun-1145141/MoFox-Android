import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/domain/system_stats.dart';
import '../../features/file_manager/domain/rootfs_file_exception.dart';
import '../../features/file_manager/domain/rootfs_file_models.dart';
import '../../features/file_manager/domain/rootfs_file_scope.dart';
import '../../features/file_manager/domain/rootfs_relative_path.dart';
import '../utils/app_logger.dart';

/// 与原生 `RuntimeBridgePlugin` 对话的方法通道单例。
///
/// 通道协议见 `android/app/src/main/kotlin/.../runtime/RuntimeBridgePlugin.kt`。
class RuntimeBridge {
  RuntimeBridge._();

  static const MethodChannel _channel = MethodChannel('mofox/runtime');
  static const EventChannel _events = EventChannel('mofox/runtime/events');

  /// 原生 RuntimeEventBus 只有一个 EventSink，因此整个 Flutter 进程必须只调用一次
  /// receiveBroadcastStream。安装日志、托管进程日志和 PTY 输出都从这条共享流过滤。
  ///
  /// 如果每个 topic 各建一条平台订阅，后建立的订阅会覆盖原生 sink；其中任意一条
  /// cancel 时又会把 sink 清空，导致安装完成后 Bot/NapCat 已启动却收不到任何日志，
  /// 直到 App 重启重新订阅。
  static final Stream<Object?> _eventStream = _events.receiveBroadcastStream();
  static int _nextFileRequestId = 0;

  /// rootfs 是否已解压完成。
  Future<bool> isBootstrapped() async {
    final result = await _channel.invokeMethod<bool>('isBootstrapped');
    return result ?? false;
  }

  /// 解压内嵌 bootstrap zip 到 `filesDir/usr`。
  ///
  /// 返回流向上抛 0..1 的进度（0 = 校验, 1 = 完成）。
  Stream<double> installBootstrap() {
    return _eventStream
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
    return _eventStream
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
    }).where((event) => event.task.isNotEmpty && event.line.isNotEmpty);
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

  /// 取消正在进行的 NapCat 扫码登录任务。
  Future<void> cancelNapcatLogin() {
    appLogger.i('runtime: cancelNapcatLogin');
    return _channel.invokeMethod<void>('cancelNapcatLogin');
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
    return _eventStream
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
    }).where((event) => event.name.isNotEmpty && event.line.isNotEmpty);
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
    return _eventStream
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

  /// 读取 rootfs 内文件的原始字节，供备份二进制配置和登录态使用。
  Future<Uint8List> readFileBytes(String rootfsPath) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'readFileBytes',
      <String, Object>{'path': rootfsPath},
    );
    return result ?? Uint8List(0);
  }

  /// 将一批文件写入 rootfs。
  ///
  /// 原生端会再次校验所有目标路径都位于 rootfs 内，并使用临时文件替换，
  /// 避免 ZIP 路径穿越或写入中断留下半截文件。
  Future<int> writeFiles(List<RootfsFileWrite> files) async {
    final result = await _channel.invokeMethod<int>(
      'writeFiles',
      <String, Object>{
        'files': files
            .map(
              (file) => <String, Object>{
                'path': file.path,
                'bytes': file.bytes,
              },
            )
            .toList(growable: false),
      },
    );
    return result ?? 0;
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

  Future<RootfsDirectoryPage> listDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int limit = 200,
    String? cursor,
  }) =>
      _invokeFileMethod<RootfsDirectoryPage>(
        'listDirectory',
        <String, Object?>{
          'scope': scope.toChannelMap(),
          'pathSegments': path.toChannelList(),
          'limit': limit,
          'cursor': cursor,
        },
        (payload) {
          final map = _requireMap(payload, 'listDirectory payload');
          final entries = _requireList(map['entries'], 'entries')
              .map((entry) => _decodeFileEntry(_requireMap(entry, 'entry')))
              .toList(growable: false);
          return RootfsDirectoryPage(
            entries: entries,
            nextCursor: _optionalString(map['nextCursor'], 'nextCursor'),
            directoryModifiedAt: _decodeMillis(
              map['directoryModifiedAt'],
              'directoryModifiedAt',
            ),
          );
        },
      );

  Future<RootfsFileEntry> statPath({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
  }) =>
      _invokeFileMethod<RootfsFileEntry>(
        'statPath',
        <String, Object>{
          'scope': scope.toChannelMap(),
          'pathSegments': path.toChannelList(),
        },
        (payload) => _decodeFileEntry(_requireMap(payload, 'statPath payload')),
      );

  Future<RootfsDocument> readTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int maxBytes = 1024 * 1024,
  }) =>
      _invokeFileMethod<RootfsDocument>(
        'readTextDocument',
        <String, Object>{
          'scope': scope.toChannelMap(),
          'pathSegments': path.toChannelList(),
          'maxBytes': maxBytes,
        },
        (payload) {
          final map = _requireMap(payload, 'readTextDocument payload');
          final encoding = _requireString(map['encoding'], 'encoding');
          if (encoding != 'utf-8') {
            throw const FormatException('原生层返回了不支持的文本编码');
          }
          return RootfsDocument(
            text: _requireString(map['text'], 'text'),
            hasUtf8Bom: _requireBool(map['hasUtf8Bom'], 'hasUtf8Bom'),
            newlineStyle: RootfsNewlineStyle.fromWireName(
              _requireString(map['newlineStyle'], 'newlineStyle'),
            ),
            hasFinalNewline:
                _requireBool(map['hasFinalNewline'], 'hasFinalNewline'),
            sizeBytes: _requireInt(map['sizeBytes'], 'sizeBytes'),
            modifiedAt: _decodeMillis(map['modifiedAt'], 'modifiedAt'),
            revision:
                RootfsRevision(_requireString(map['revision'], 'revision')),
          );
        },
      );

  Future<RootfsWriteResult> writeTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String text,
    required bool hasUtf8Bom,
    required RootfsWriteMode writeMode,
    RootfsRevision? expectedRevision,
  }) =>
      _invokeFileMethod<RootfsWriteResult>(
        'writeTextDocument',
        <String, Object?>{
          'scope': scope.toChannelMap(),
          'pathSegments': path.toChannelList(),
          'text': text,
          'hasUtf8Bom': hasUtf8Bom,
          'writeMode': writeMode.wireName,
          'expectedRevision': expectedRevision?.value,
        },
        (payload) {
          final map = _requireMap(payload, 'writeTextDocument payload');
          return RootfsWriteResult(
            revision:
                RootfsRevision(_requireString(map['revision'], 'revision')),
            sizeBytes: _requireInt(map['sizeBytes'], 'sizeBytes'),
            modifiedAt: _decodeMillis(map['modifiedAt'], 'modifiedAt'),
          );
        },
      );

  Future<void> createDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath parentPath,
    required String name,
  }) =>
      _invokeFileMethod(
        'createDirectory',
        <String, Object>{
          'scope': scope.toChannelMap(),
          'parentPathSegments': parentPath.toChannelList(),
          'name': name,
        },
        _requireNullPayload,
      );

  Future<void> renameEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String newName,
  }) =>
      _invokeFileMethod(
        'renameEntry',
        <String, Object>{
          'scope': scope.toChannelMap(),
          'pathSegments': path.toChannelList(),
          'newName': newName,
        },
        _requireNullPayload,
      );

  Future<void> deleteEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required bool recursive,
  }) =>
      _invokeFileMethod(
        'deleteEntry',
        <String, Object>{
          'scope': scope.toChannelMap(),
          'pathSegments': path.toChannelList(),
          'recursive': recursive,
        },
        _requireNullPayload,
      );

  Future<T> _invokeFileMethod<T>(
    String method,
    Map<String, Object?> arguments,
    T Function(Object? payload) decodePayload,
  ) async {
    final requestId =
        'dart-${DateTime.now().microsecondsSinceEpoch}-${_nextFileRequestId++}';
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        <String, Object?>{...arguments, 'requestId': requestId},
      );
      final envelope = _requireMap(result, '$method response');
      final responseId = _requireString(envelope['requestId'], 'requestId');
      if (responseId != requestId) {
        throw RootfsFileException(
          code: RootfsFileErrorCode.malformedResponse,
          message: '文件服务响应与请求不匹配',
          operation: method,
          requestId: responseId,
        );
      }
      return decodePayload(envelope['payload']);
    } on PlatformException catch (error) {
      throw _decodeFileException(error, fallbackRequestId: requestId);
    } on RootfsFileException {
      rethrow;
    } on FormatException catch (error) {
      throw RootfsFileException(
        code: RootfsFileErrorCode.malformedResponse,
        message: '文件服务返回了无效数据：${error.message}',
        operation: method,
        requestId: requestId,
      );
    } on RangeError catch (error) {
      // RangeError 必须在 ArgumentError 之前，因为它是 ArgumentError 的子类。
      throw RootfsFileException(
        code: RootfsFileErrorCode.malformedResponse,
        message: '文件服务返回了越界数据：$error',
        operation: method,
        requestId: requestId,
      );
    } on ArgumentError catch (error) {
      throw RootfsFileException(
        code: RootfsFileErrorCode.malformedResponse,
        message: '文件服务返回了无效数据：$error',
        operation: method,
        requestId: requestId,
      );
    }
  }
}

void _requireNullPayload(Object? payload) {
  if (payload != null) {
    throw const FormatException('文件操作成功响应的 payload 应为空');
  }
}

RootfsFileEntry _decodeFileEntry(Map<Object?, Object?> map) {
  final path = _requireList(map['pathSegments'], 'pathSegments')
      .map((segment) => _requireString(segment, 'path segment'));
  return RootfsFileEntry(
    name: _requireString(map['name'], 'name'),
    relativePath: RootfsRelativePath(path),
    kind: RootfsFileKind.fromWireName(_requireString(map['kind'], 'kind')),
    sizeBytes: _optionalInt(map['sizeBytes'], 'sizeBytes'),
    modifiedAt: _decodeMillis(map['modifiedAt'], 'modifiedAt'),
    isHidden: _requireBool(map['isHidden'], 'isHidden'),
  );
}

RootfsFileException _decodeFileException(
  PlatformException error, {
  required String fallbackRequestId,
}) {
  final details = error.details;
  final map =
      details is Map<Object?, Object?> ? details : const <Object?, Object?>{};
  return RootfsFileException(
    code: RootfsFileErrorCode.fromWireName(error.code),
    message: error.message ?? '文件操作失败',
    operation: map['operation'] is String ? map['operation']! as String : null,
    scopeId: map['scopeId'] is String ? map['scopeId']! as String : null,
    relativePath:
        map['relativePath'] is String ? map['relativePath']! as String : null,
    retryable: map['retryable'] == true,
    currentRevision: map['currentRevision'] is String
        ? map['currentRevision']! as String
        : null,
    requestId: map['requestId'] is String
        ? map['requestId']! as String
        : fallbackRequestId,
  );
}

Map<Object?, Object?> _requireMap(Object? value, String field) {
  if (value is Map<Object?, Object?>) return value;
  throw FormatException('$field 不是对象');
}

List<Object?> _requireList(Object? value, String field) {
  if (value is List<Object?>) return value;
  throw FormatException('$field 不是数组');
}

String _requireString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field 不是字符串');
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  return _requireString(value, field);
}

bool _requireBool(Object? value, String field) {
  if (value is bool) return value;
  throw FormatException('$field 不是布尔值');
}

int _requireInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field 不是整数');
}

int? _optionalInt(Object? value, String field) {
  if (value == null) return null;
  return _requireInt(value, field);
}

DateTime _decodeMillis(Object? value, String field) =>
    DateTime.fromMillisecondsSinceEpoch(_requireInt(value, field));

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

class RootfsFileWrite {
  const RootfsFileWrite({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}
