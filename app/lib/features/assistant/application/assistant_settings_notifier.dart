import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/assistant_credential_store.dart';

const int assistantYoloConsentVersion = 2;

enum AssistantOperationMode { copilot, yolo }

class AssistantSettings {
  const AssistantSettings({
    required this.enabled,
    required this.baseUrl,
    required this.model,
    required this.mode,
    required this.hasApiKey,
    required this.yoloConsentVersion,
    required this.allowInsecureHttp,
  });

  final bool enabled;
  final String baseUrl;
  final String model;
  final AssistantOperationMode mode;
  final bool hasApiKey;
  final int yoloConsentVersion;
  final bool allowInsecureHttp;

  bool get configured =>
      enabled &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      hasApiKey;

  bool get yoloEnabled =>
      mode == AssistantOperationMode.yolo &&
      yoloConsentVersion == assistantYoloConsentVersion;

  AssistantSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? model,
    AssistantOperationMode? mode,
    bool? hasApiKey,
    int? yoloConsentVersion,
    bool? allowInsecureHttp,
  }) {
    return AssistantSettings(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      mode: mode ?? this.mode,
      hasApiKey: hasApiKey ?? this.hasApiKey,
      yoloConsentVersion: yoloConsentVersion ?? this.yoloConsentVersion,
      allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
    );
  }
}

class AssistantSettingsNotifier extends AsyncNotifier<AssistantSettings> {
  static const String _enabledKey = 'assistant_enabled';
  static const String _baseUrlKey = 'assistant_base_url';
  static const String _modelKey = 'assistant_model';
  static const String _modeKey = 'assistant_mode';
  static const String _consentKey = 'assistant_yolo_consent_version';
  static const String _insecureHttpKey = 'assistant_allow_insecure_http';

  final AssistantCredentialStore _credentials =
      const AssistantCredentialStore();

  @override
  Future<AssistantSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_modeKey);
    return AssistantSettings(
      enabled: prefs.getBool(_enabledKey) ?? false,
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      model: prefs.getString(_modelKey) ?? '',
      mode: modeName == AssistantOperationMode.yolo.name
          ? AssistantOperationMode.yolo
          : AssistantOperationMode.copilot,
      hasApiKey: (await _credentials.read())?.isNotEmpty == true,
      yoloConsentVersion: prefs.getInt(_consentKey) ?? 0,
      allowInsecureHttp: prefs.getBool(_insecureHttpKey) ?? false,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = state.valueOrNull ?? _empty();
    state = AsyncData(previous.copyWith(enabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setBool(_enabledKey, enabled);
    } on Object {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> setAllowInsecureHttp(bool enabled) async {
    final previous = state.valueOrNull ?? _empty();
    state = AsyncData(previous.copyWith(allowInsecureHttp: enabled));
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setBool(_insecureHttpKey, enabled);
    } on Object {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> saveConnection({
    required bool enabled,
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setString(_baseUrlKey, baseUrl.trim());
    await prefs.setString(_modelKey, model.trim());
    var hasApiKey = state.valueOrNull?.hasApiKey ?? false;
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _credentials.write(apiKey.trim());
      hasApiKey = true;
    }
    state = AsyncData(
      (state.valueOrNull ?? _empty()).copyWith(
        enabled: enabled,
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        hasApiKey: hasApiKey,
      ),
    );
  }

  Future<void> enableYolo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, AssistantOperationMode.yolo.name);
    await prefs.setInt(_consentKey, assistantYoloConsentVersion);
    state = AsyncData(
      (state.valueOrNull ?? _empty()).copyWith(
        mode: AssistantOperationMode.yolo,
        yoloConsentVersion: assistantYoloConsentVersion,
      ),
    );
  }

  Future<void> disableYolo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, AssistantOperationMode.copilot.name);
    state = AsyncData(
      (state.valueOrNull ?? _empty()).copyWith(
        mode: AssistantOperationMode.copilot,
      ),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.remove(_enabledKey),
      prefs.remove(_baseUrlKey),
      prefs.remove(_modelKey),
      prefs.remove(_modeKey),
      prefs.remove(_consentKey),
      prefs.remove(_insecureHttpKey),
    ]);
    await _credentials.delete();
    state = AsyncData(_empty());
  }

  AssistantSettings _empty() => const AssistantSettings(
        enabled: false,
        baseUrl: '',
        model: '',
        mode: AssistantOperationMode.copilot,
        hasApiKey: false,
        yoloConsentVersion: 0,
        allowInsecureHttp: false,
      );
}

final assistantSettingsProvider =
    AsyncNotifierProvider<AssistantSettingsNotifier, AssistantSettings>(
  AssistantSettingsNotifier.new,
);

final assistantCredentialStoreProvider = Provider<AssistantCredentialStore>(
  (_) => const AssistantCredentialStore(),
);
