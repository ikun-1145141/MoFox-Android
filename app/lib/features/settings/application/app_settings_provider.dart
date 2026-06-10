import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _terminalHapticsKey = 'terminal_haptics_enabled';

class AppSettings {
  const AppSettings({required this.terminalHapticsEnabled});

  final bool terminalHapticsEnabled;
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      terminalHapticsEnabled: prefs.getBool(_terminalHapticsKey) ?? true,
    );
  }

  Future<void> setTerminalHapticsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_terminalHapticsKey, enabled);
    state = AsyncData(AppSettings(terminalHapticsEnabled: enabled));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
