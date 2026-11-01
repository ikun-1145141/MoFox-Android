import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModeKey = 'theme_mode';
const String _dynamicColorKey = 'dynamic_color_enabled';
const String _mainImageModeKey = 'main_image_mode';
const String _terminalHapticsKey = 'terminal_haptics_enabled';
const String _lockScreenKeepAliveKey = 'lockScreenKeepAlive';
const String _deviceCapabilityEnabledKey = 'device_capability_enabled';
const String _deviceCapabilityNotificationsKey =
    'device_capability_notifications_enabled';
const String _deviceCapabilitySmsKey = 'device_capability_sms_enabled';

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
    required this.lockScreenKeepAlive,
    required this.deviceCapabilityEnabled,
    required this.deviceCapabilityNotificationsEnabled,
    required this.deviceCapabilitySmsEnabled,
  });

  final AppThemeMode themeMode;
  final bool dynamicColorEnabled;
  final MainImageMode mainImageMode;
  final bool terminalHapticsEnabled;

  /// 锁屏保活：实例运行期间持有 CPU partial wake lock，锁屏不进深度休眠。
  final bool lockScreenKeepAlive;

  /// 设备能力服务总开关：关闭时本机服务不启动，数据源一律不采集。
  final bool deviceCapabilityEnabled;

  /// 通知源：捕获应用通知供 bot 实例读取。仅总开关开启时生效。
  final bool deviceCapabilityNotificationsEnabled;

  /// 短信源：读取新短信供 bot 实例读取。仅总开关开启时生效。
  final bool deviceCapabilitySmsEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? dynamicColorEnabled,
    MainImageMode? mainImageMode,
    bool? terminalHapticsEnabled,
    bool? lockScreenKeepAlive,
    bool? deviceCapabilityEnabled,
    bool? deviceCapabilityNotificationsEnabled,
    bool? deviceCapabilitySmsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      dynamicColorEnabled: dynamicColorEnabled ?? this.dynamicColorEnabled,
      mainImageMode: mainImageMode ?? this.mainImageMode,
      terminalHapticsEnabled:
          terminalHapticsEnabled ?? this.terminalHapticsEnabled,
      lockScreenKeepAlive:
          lockScreenKeepAlive ?? this.lockScreenKeepAlive,
      deviceCapabilityEnabled:
          deviceCapabilityEnabled ?? this.deviceCapabilityEnabled,
      deviceCapabilityNotificationsEnabled:
          deviceCapabilityNotificationsEnabled ??
              this.deviceCapabilityNotificationsEnabled,
      deviceCapabilitySmsEnabled:
          deviceCapabilitySmsEnabled ?? this.deviceCapabilitySmsEnabled,
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
      lockScreenKeepAlive: prefs.getBool(_lockScreenKeepAliveKey) ?? false,
      deviceCapabilityEnabled:
          prefs.getBool(_deviceCapabilityEnabledKey) ?? false,
      deviceCapabilityNotificationsEnabled:
          prefs.getBool(_deviceCapabilityNotificationsKey) ?? false,
      deviceCapabilitySmsEnabled:
          prefs.getBool(_deviceCapabilitySmsKey) ?? false,
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

  Future<void> setLockScreenKeepAlive(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockScreenKeepAliveKey, enabled);
    _update((settings) => settings.copyWith(lockScreenKeepAlive: enabled));
  }

  Future<void> setDeviceCapabilityEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceCapabilityEnabledKey, enabled);
    _update((settings) => settings.copyWith(deviceCapabilityEnabled: enabled));
  }

  Future<void> setDeviceCapabilityNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceCapabilityNotificationsKey, enabled);
    _update(
      (settings) => settings.copyWith(deviceCapabilityNotificationsEnabled: enabled),
    );
  }

  Future<void> setDeviceCapabilitySmsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceCapabilitySmsKey, enabled);
    _update(
      (settings) => settings.copyWith(deviceCapabilitySmsEnabled: enabled),
    );
  }

  void _update(AppSettings Function(AppSettings settings) update) {
    final current = state.valueOrNull;
    if (current == null) {
      // 设置已经成功写入 SharedPreferences，但首次加载可能仍在
      // 进行，或上一次加载失败。重建 Provider 以便 UI 不会永久
      // 停在“加载中”或忽略用户刚刚的操作。
      ref.invalidateSelf();
      return;
    }
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
