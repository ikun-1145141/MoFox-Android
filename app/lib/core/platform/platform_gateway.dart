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

  /// 通过 SAF 让用户选文件后读取内容。返回文件字节；用户取消返回 `null`。
  Future<Uint8List?> importFromSaf() async {
    final result = await _channel.invokeMethod<List<Object?>>('importFromSaf');
    if (result == null) return null;
    return Uint8List.fromList(result.cast<int>());
  }

  /// 跳系统设置页（自启动 / 耗电管理 / 后台锁定），按厂商分发。
  Future<void> openVendorAutostart() =>
      _channel.invokeMethod<void>('openVendorAutostart');

  /// 请求加入系统电池优化白名单；已授权时返回 true。
  Future<bool> requestIgnoreBatteryOptimizations() async {
    return await _channel.invokeMethod<bool>(
          'requestIgnoreBatteryOptimizations',
        ) ??
        false;
  }

  Future<KeepaliveStatus> getKeepaliveStatus() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getKeepaliveStatus',
    );
    return KeepaliveStatus.fromMap(result ?? const <String, Object?>{});
  }

  Future<void> startForegroundService() =>
      _channel.invokeMethod<void>('startForegroundService');

  Future<void> stopForegroundService() =>
      _channel.invokeMethod<void>('stopForegroundService');

  Future<void> setKeepScreenOn({required bool enabled}) =>
      _channel.invokeMethod<void>('setKeepScreenOn', <String, Object>{
        'enabled': enabled,
      });
}

final platformGatewayProvider =
    Provider<PlatformGateway>((_) => PlatformGateway._());

class KeepaliveStatus {
  const KeepaliveStatus({
    required this.notificationsGranted,
    required this.ignoringBatteryOptimizations,
    required this.foregroundServiceEnabled,
    required this.bootReceiverDeclared,
    required this.vendorAutostartInspectable,
  });

  factory KeepaliveStatus.fromMap(Map<String, Object?> map) {
    return KeepaliveStatus(
      notificationsGranted: map['notificationsGranted'] == true,
      ignoringBatteryOptimizations: map['ignoringBatteryOptimizations'] == true,
      foregroundServiceEnabled: map['foregroundServiceEnabled'] == true,
      bootReceiverDeclared: map['bootReceiverDeclared'] == true,
      vendorAutostartInspectable: map['vendorAutostartInspectable'] == true,
    );
  }

  final bool notificationsGranted;
  final bool ignoringBatteryOptimizations;
  final bool foregroundServiceEnabled;
  final bool bootReceiverDeclared;
  final bool vendorAutostartInspectable;
}
