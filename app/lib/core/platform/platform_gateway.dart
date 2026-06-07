import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 与原生层的非 runtime 平台能力对话：SAF 导出 / 厂商保活引导 / 前台服务开关。
class PlatformGateway {
  PlatformGateway._();

  static const MethodChannel _channel = MethodChannel('mofox/platform');

  /// 通过 SAF 让用户选目录后落 zip。返回 content URI；用户取消返回 `null`。
  Future<String?> exportToSaf({
    required String suggestedName,
    required List<int> bytes,
  }) {
    return _channel.invokeMethod<String>('exportToSaf', <String, Object>{
      'suggestedName': suggestedName,
      'bytes': Uint8List.fromList(bytes),
    });
  }

  /// 跳系统设置页（自启动 / 耗电管理 / 后台锁定），按厂商分发。
  Future<void> openVendorAutostart() =>
      _channel.invokeMethod<void>('openVendorAutostart');

  Future<void> startForegroundService() =>
      _channel.invokeMethod<void>('startForegroundService');

  Future<void> stopForegroundService() =>
      _channel.invokeMethod<void>('stopForegroundService');
}

final platformGatewayProvider =
    Provider<PlatformGateway>((_) => PlatformGateway._());
