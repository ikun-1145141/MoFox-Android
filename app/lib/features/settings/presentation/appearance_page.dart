import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/settings/application/app_settings_provider.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: asyncSettings.when(
        loading: () => const AppLoadingState(label: '正在加载外观设置'),
        error: (_, __) => AppErrorState(
          title: '外观设置加载失败',
          message: '暂时无法读取已保存的主题设置。',
          onRetry: () => ref.invalidate(appSettingsProvider),
        ),
        data: (settings) => AppPageList(
          children: <Widget>[
            _AppearancePreview(settings: settings),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: '主题模式',
              addDividers: false,
              contentPadding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<AppThemeMode>(
                    segments: AppThemeMode.values
                        .map(
                          (mode) => ButtonSegment<AppThemeMode>(
                            value: mode,
                            icon: Icon(_themeModeIcon(mode)),
                            label: Text(mode.label),
                          ),
                        )
                        .toList(),
                    selected: <AppThemeMode>{settings.themeMode},
                    onSelectionChanged: (selection) => _persist(
                      context,
                      () => ref
                          .read(appSettingsProvider.notifier)
                          .setThemeMode(selection.single),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: '颜色',
              addDividers: false,
              children: <Widget>[
                AppSwitchSettingTile(
                  secondary: const Icon(Icons.format_color_fill_outlined),
                  title: '动态取色',
                  subtitle: 'Android 12 及以上使用系统壁纸生成 Material You 颜色',
                  value: settings.dynamicColorEnabled,
                  onChanged: (value) => _persist(
                    context,
                    () => ref
                        .read(appSettingsProvider.notifier)
                        .setDynamicColorEnabled(value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: '主图模式',
              addDividers: false,
              children: <Widget>[
                RadioGroup<MainImageMode>(
                  groupValue: settings.mainImageMode,
                  onChanged: (value) {
                    if (value == null) return;
                    _persist(
                      context,
                      () => ref
                          .read(appSettingsProvider.notifier)
                          .setMainImageMode(value),
                    );
                  },
                  child: Column(
                    children: MainImageMode.values
                        .map(
                          (mode) => RadioListTile<MainImageMode>(
                            value: mode,
                            title: Text(mode.label),
                            subtitle: Text(mode.description),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _persist(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存外观设置失败，请重试')),
      );
    }
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final showHero = settings.mainImageMode != MainImageMode.hidden;
    final compact = settings.mainImageMode == MainImageMode.compact;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.card),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.preview_outlined, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '预览',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (showHero) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                height: compact ? 76 : 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  gradient: LinearGradient(
                    colors: <Color>[
                      scheme.primaryContainer,
                      scheme.tertiaryContainer,
                    ],
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: scheme.surface,
                        shape: const StadiumBorder(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          'MoFox',
                          style: text.titleLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _PreviewChip(label: settings.themeMode.label),
                _PreviewChip(
                  label: settings.dynamicColorEnabled ? '动态取色' : '品牌色',
                ),
                _PreviewChip(label: settings.mainImageMode.label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: scheme.secondaryContainer,
      labelStyle: TextStyle(color: scheme.onSecondaryContainer),
      side: BorderSide.none,
    );
  }
}

IconData _themeModeIcon(AppThemeMode mode) {
  return switch (mode) {
    AppThemeMode.system => Icons.brightness_auto_outlined,
    AppThemeMode.light => Icons.light_mode_outlined,
    AppThemeMode.dark => Icons.dark_mode_outlined,
  };
}
