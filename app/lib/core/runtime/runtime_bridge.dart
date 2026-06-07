import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 与原生 `RuntimeBridgePlugin` 对话的方法通道单例。
///
/// 通道协议见 `android/app/src/main/kotlin/.../runtime/RuntimeBridgePlugin.kt`。
class RuntimeBridge {
  RuntimeBridge._();

  static const MethodChannel _channel =
      MethodChannel('mofox/runtime');
  static const EventChannel _events =
      EventChannel('mofox/runtime/events');

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
        .cast<double>();
  }

  /// 启动 / 停止 / 重启托管进程。`name` ∈ {bot, napcat}.
  Future<void> startProcess(String name) =>
      _channel.invokeMethod<void>('startProcess', <String, Object>{'name': name});
  Future<void> stopProcess(String name) =>
      _channel.invokeMethod<void>('stopProcess', <String, Object>{'name': name});
  Future<void> restartProcess(String name) =>
      _channel.invokeMethod<void>('restartProcess', <String, Object>{'name': name});

  /// 拉一份当前各托管进程的状态快照。
  Future<Map<String, String>> processStatus() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('processStatus');
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
        .cast<String>();
  }

  Future<String> openPty({String shell = '/data/data/com.mofox.android/files/usr/bin/bash'}) async {
    final id = await _channel.invokeMethod<String>('openPty', <String, Object>{'shell': shell});
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

  Future<void> closePty(String sessionId) =>
      _channel.invokeMethod<void>('closePty', <String, Object>{'sessionId': sessionId});
}

final runtimeBridgeProvider = Provider<RuntimeBridge>((_) => RuntimeBridge._());
