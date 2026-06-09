import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          final line = payload['line']?.toString() ?? '';
          return InstallEvent(task: task, line: line);
        })
        .where((event) => event.task.isNotEmpty && event.line.isNotEmpty);
  }

  /// 启动 / 停止 / 重启托管进程。`name` ∈ {bot, napcat}.
  Future<void> startProcess(String name) => _channel.invokeMethod<void>(
        'startProcess',
        <String, Object>{'name': name},
      );

  Future<void> stopProcess(String name) => _channel.invokeMethod<void>(
        'stopProcess',
        <String, Object>{'name': name},
      );

  Future<void> restartProcess(String name) => _channel.invokeMethod<void>(
        'restartProcess',
        <String, Object>{'name': name},
      );

  /// 拉一份当前各托管进程的状态快照。
  Future<Map<String, String>> processStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('processStatus');
    return result?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
        const <String, String>{};
  }

  /// PTY 流：终端页订阅这个，收 stdout，往 [writePty] 写 stdin。
  Stream<String> ptyOutput(String sessionId) {
    return _events
        .receiveBroadcastStream(<String, Object?>{
          'topic': 'pty',
          'sessionId': sessionId,
        })
        .where(
          (event) => event is Map<Object?, Object?> && event['topic'] == 'pty',
        )
        .map(
          (event) =>
              (event as Map<Object?, Object?>)['payload']?.toString() ?? '',
        );
  }

  Future<String> openPty({
    String shell = '/data/data/com.mofox.android/files/usr/bin/bash',
  }) async {
    final id = await _channel.invokeMethod<String>(
      'openPty',
      <String, Object>{'shell': shell},
    );
    return id ?? '';
  }

  Future<void> writePty(String sessionId, String data) =>
      _channel.invokeMethod<void>('writePty', <String, Object>{
        'sessionId': sessionId,
        'data': data,
      });

  Future<void> resizePty(String sessionId, int cols, int rows) =>
      _channel.invokeMethod<void>('resizePty', <String, Object>{
        'sessionId': sessionId,
        'cols': cols,
        'rows': rows,
      });

  Future<void> closePty(String sessionId) => _channel.invokeMethod<void>(
        'closePty',
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
          ? rawLogs.map((line) => line.toString()).toList()
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
