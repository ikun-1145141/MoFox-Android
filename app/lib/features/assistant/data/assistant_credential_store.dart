import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AssistantCredentialStore {
  const AssistantCredentialStore();

  static const String _key = 'assistant_api_key_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String value) => _storage.write(key: _key, value: value);

  Future<void> delete() => _storage.delete(key: _key);
}
