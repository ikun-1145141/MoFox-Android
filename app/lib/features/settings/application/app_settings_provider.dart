import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModeKey = 'theme_mode';
const String _dynamicColorKey = 'dynamic_color_enabled';
const String _mainImageModeKey = 'main_image_mode';
const String _terminalHapticsKey = 'terminal_haptics_enabled';

enum AppThemeMode {
  system,
  light,
  dark;

  String get label => switch (this) {
        AppThemeMode.system => '跟随系统',
        AppThemeMode.light => '浅色',
        AppThemeMode.dark => '深色',
      };
}

enum MainImageMode {
  expressive,
  compact,
  hidden;

  String get label => switch (this) {
        MainImageMode.expressive => '沉浸主图',
        MainImageMode.compact => '紧凑主图',
        MainImageMode.hidden => '隐藏主图',
      };

  String get description => switch (this) {
        MainImageMode.expressive => '首页与卡片使用更醒目的主题视觉',
        MainImageMode.compact => '保留主题色块，但减少占用空间',
        MainImageMode.hidden => '减少装饰，只保留内容本身',
      };
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.dynamicColorEnabled,
    required this.mainImageMode,
    required this.terminalHapticsEnabled,
  });

  final AppThemeMode themeMode;
  final bool dynamicColorEnabled;
  final MainImageMode mainImageMode;
  final bool terminalHapticsEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? dynamicColorEnabled,
    MainImageMode? mainImageMode,
    bool? terminalHapticsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      dynamicColorEnabled: dynamicColorEnabled ?? this.dynamicColorEnabled,
      mainImageMode: mainImageMode ?? this.mainImageMode,
      terminalHapticsEnabled:
          terminalHapticsEnabled ?? this.terminalHapticsEnabled,
    );
  }
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _readEnum(
        prefs.getString(_themeModeKey),
        AppThemeMode.values,
        AppThemeMode.system,
      ),
      dynamicColorEnabled: prefs.getBool(_dynamicColorKey) ?? true,
      mainImageMode: _readEnum(
        prefs.getString(_mainImageModeKey),
        MainImageMode.values,
        MainImageMode.expressive,
      ),
      terminalHapticsEnabled: prefs.getBool(_terminalHapticsKey) ?? true,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    _update((settings) => settings.copyWith(themeMode: mode));
  }

  Future<void> setDynamicColorEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dynamicColorKey, enabled);
    _update((settings) => settings.copyWith(dynamicColorEnabled: enabled));
  }

  Future<void> setMainImageMode(MainImageMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mainImageModeKey, mode.name);
    _update((settings) => settings.copyWith(mainImageMode: mode));
  }

  Future<void> setTerminalHapticsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_terminalHapticsKey, enabled);
    _update((settings) => settings.copyWith(terminalHapticsEnabled: enabled));
  }

  void _update(AppSettings Function(AppSettings settings) update) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(update(current));
  }
}

T _readEnum<T extends Enum>(String? value, List<T> values, T fallback) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  return fallback;
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
