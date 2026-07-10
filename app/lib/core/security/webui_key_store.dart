import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 用 [FlutterSecureStorage]（AndroidKeystore 加密）安全存储每个实例的
/// WebUI api_key，避免明文落 SharedPreferences。
///
/// key 格式：`webui_apikey_<instanceId>`。
class WebuiKeyStore {
  const WebuiKeyStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 读取实例的 WebUI api_key，不存在返回 null。
  static Future<String?> get(String instanceId) async {
    return _storage.read(key: 'webui_apikey_$instanceId');
  }

  /// 写入实例的 WebUI api_key。
  static Future<void> set(String instanceId, String apiKey) async {
    await _storage.write(key: 'webui_apikey_$instanceId', value: apiKey);
  }

  /// 删除实例的 WebUI api_key。
  static Future<void> delete(String instanceId) async {
    await _storage.delete(key: 'webui_apikey_$instanceId');
  }
}
