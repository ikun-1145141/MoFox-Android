import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_settings_provider.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: SafeArea(
        child: asyncSettings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('加载失败：$error')),
          data: (settings) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _AppearancePreview(settings: settings),
              const SizedBox(height: 16),
              _Section(
                title: '主题模式',
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
                  onSelectionChanged: (selection) => ref
                      .read(appSettingsProvider.notifier)
                      .setThemeMode(selection.single),
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: '颜色',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.format_color_fill_outlined),
                  title: const Text('动态取色'),
                  subtitle: const Text('Android 12+ 使用系统壁纸生成 Material You 颜色'),
                  value: settings.dynamicColorEnabled,
                  onChanged: (value) => ref
                      .read(appSettingsProvider.notifier)
                      .setDynamicColorEnabled(value),
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: '主图模式',
                child: Column(
                  children: MainImageMode.values
                      .map(
                        (mode) => RadioListTile<MainImageMode>(
                          contentPadding: EdgeInsets.zero,
                          value: mode,
                          groupValue: settings.mainImageMode,
                          onChanged: (value) {
                            if (value == null) return;
                            ref
                                .read(appSettingsProvider.notifier)
                                .setMainImageMode(value);
                          },
                          title: Text(mode.label),
                          subtitle: Text(mode.description),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.preview_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '预览',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (showHero) ...<Widget>[
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: compact ? 76 : 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
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
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'MoFox',
                      style: text.headlineSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: child,
          ),
        ),
      ],
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
