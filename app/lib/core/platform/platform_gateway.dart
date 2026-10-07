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

  /// 读取手机短信桥接状态（权限 / 运行时 / 桥接文件）。
  Future<SmsBridgeStatus> getSmsBridgeStatus() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getSmsBridgeStatus',
    );
    return SmsBridgeStatus.fromMap(result ?? const <String, Object?>{});
  }

  /// 开关短信桥接。开启前请先确认已获得「短信」运行时权限。
  Future<void> setSmsBridgeEnabled({required bool enabled}) =>
      _channel.invokeMethod<void>('setSmsBridgeEnabled', <String, Object>{
        'enabled': enabled,
      });

  /// 注入一条模拟快递短信事件，验证「短信 → 桥接文件 → Bot 主动私信」链路。
  Future<bool> sendSmsBridgeTest() async {
    return await _channel.invokeMethod<bool>('sendSmsBridgeTest') ?? false;
  }
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

class SmsBridgeStatus {
  const SmsBridgeStatus({
    required this.enabled,
    required this.smsPermissionGranted,
    required this.rootfsReady,
    required this.bridgeFileExists,
    required this.bridgeFileSize,
    required this.usable,
  });

  factory SmsBridgeStatus.fromMap(Map<String, Object?> map) {
    return SmsBridgeStatus(
      enabled: map['enabled'] == true,
      smsPermissionGranted: map['smsPermissionGranted'] == true,
      rootfsReady: map['rootfsReady'] == true,
      bridgeFileExists: map['bridgeFileExists'] == true,
      bridgeFileSize: (map['bridgeFileSize'] as num?)?.toInt() ?? 0,
      usable: map['usable'] == true,
    );
  }

  /// 桥接开关是否已打开（与短信权限相互独立）。
  final bool enabled;

  /// 是否已获得 android.permission.RECEIVE_SMS 运行时权限。
  final bool smsPermissionGranted;

  /// rootfs 是否已解压就绪（桥接目录随 rootfs 落盘）。
  final bool rootfsReady;

  /// 桥接文件 inbox.jsonl 是否已存在。
  final bool bridgeFileExists;

  /// 桥接文件当前大小（字节）。
  final int bridgeFileSize;

  /// 权限与运行时均就绪，链路可用。
  final bool usable;
}
