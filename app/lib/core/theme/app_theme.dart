import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// MoFox 家族色：Launcher 蓝 → 渐变浅蓝。
/// 文档来源：MoFox-Bot-Docs/NEW_FEATURES.md（品牌色渐变 #367BF0 → #82B0FA）。
abstract final class BrandColors {
  static const Color seed = Color(0xFF367BF0);
  static const Color seedSoft = Color(0xFF82B0FA);
}

/// 应用级间距令牌。页面和复用组件应优先使用这里的值，避免出现近似但
/// 不一致的 10 / 14 / 18 dp 间距。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// 应用级形状令牌，对应 Material 3 从控件到大容器的圆角层级。
abstract final class AppRadii {
  static const double control = 12;
  static const double card = 20;
  static const double dialog = 28;
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

  static ThemeData highContrastLight([ColorScheme? dynamicScheme]) =>
      _build(_highContrast(dynamicScheme, Brightness.light));

  static ThemeData highContrastDark([ColorScheme? dynamicScheme]) =>
      _build(_highContrast(dynamicScheme, Brightness.dark));

  static ColorScheme _fallback(Brightness b) =>
      ColorScheme.fromSeed(seedColor: BrandColors.seed, brightness: b);

  static ColorScheme _highContrast(
    ColorScheme? dynamicScheme,
    Brightness brightness,
  ) =>
      ColorScheme.fromSeed(
        seedColor: dynamicScheme?.primary ?? BrandColors.seed,
        brightness: brightness,
        contrastLevel: 1,
      );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = base.textTheme;
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
    );
    const cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      // Android 使用支持预测返回的 Material 3 过渡；系统的“移除动画”设置
      // 仍由 Flutter 的路由动画管线统一处理。
      pageTransitionsTheme: const PageTransitionsTheme(),
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
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppRadii.control),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadii.control),
          ),
          borderSide: BorderSide(color: scheme.outline),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadii.control),
          ),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.dialog)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        shape: controlShape,
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
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          minimumSize: const Size(48, 48),
          shape: controlShape,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        minVerticalPadding: 12,
        minTileHeight: 64,
        shape: const RoundedRectangleBorder(),
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
        actionTextColor: scheme.inversePrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
        ),
      ),
    );
  }
}

/// 包一层 [DynamicColorBuilder]，统一对外暴露 light / dark scheme。
class DynamicTheme extends StatelessWidget {
  const DynamicTheme({
    required this.useDynamicColor,
    required this.builder,
    super.key,
  });
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
