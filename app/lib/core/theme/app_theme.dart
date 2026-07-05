import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// MoFox 家族色：Launcher 蓝 → 渐变浅蓝。
/// 文档来源：MoFox-Bot-Docs/NEW_FEATURES.md（品牌色渐变 #367BF0 → #82B0FA）。
abstract final class BrandColors {
  static const Color seed = Color(0xFF367BF0);
  static const Color seedSoft = Color(0xFF82B0FA);
}

/// Android 原生 Material 3 主题。
///
/// 行为：
/// - 优先采用系统取色（Android 12+ Material You）。
/// - 取不到时回落到 [BrandColors.seed] 生成的 ColorScheme。
abstract final class AppTheme {
  static ThemeData light([ColorScheme? dynamicScheme]) =>
      _build(dynamicScheme ?? _fallback(Brightness.light));

  static ThemeData dark([ColorScheme? dynamicScheme]) =>
      _build(dynamicScheme ?? _fallback(Brightness.dark));

  static ColorScheme _fallback(Brightness b) =>
      ColorScheme.fromSeed(seedColor: BrandColors.seed, brightness: b);

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = base.textTheme;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        labelType: NavigationRailLabelType.all,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          shape: const StadiumBorder(),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        minVerticalPadding: 12,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// 包一层 [DynamicColorBuilder]，统一对外暴露 light / dark scheme。
class DynamicTheme extends StatelessWidget {
  const DynamicTheme(
      {required this.useDynamicColor, required this.builder, super.key});
  final bool useDynamicColor;
  final Widget Function(BuildContext, ColorScheme light, ColorScheme dark)
      builder;

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light = useDynamicColor
            ? lightDynamic?.harmonized() ?? _seedScheme(Brightness.light)
            : _seedScheme(Brightness.light);
        final dark = useDynamicColor
            ? darkDynamic?.harmonized() ?? _seedScheme(Brightness.dark)
            : _seedScheme(Brightness.dark);
        return builder(context, light, dark);
      },
    );
  }

  ColorScheme _seedScheme(Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: BrandColors.seed,
      brightness: brightness,
    );
  }
}
