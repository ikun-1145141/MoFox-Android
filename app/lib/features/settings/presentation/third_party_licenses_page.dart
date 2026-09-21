import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:package_info_plus/package_info_plus.dart';

@immutable
class ThirdPartyLicenseItem {
  const ThirdPartyLicenseItem({
    required this.packageName,
    required this.paragraphs,
  });

  final String packageName;
  final List<LicenseParagraph> paragraphs;

  String get text => paragraphs.map((paragraph) {
        if (paragraph.indent <= 0) return paragraph.text;
        return '${'  ' * paragraph.indent}${paragraph.text}';
      }).join('\n\n');
}

@immutable
class ThirdPartyLicenseBundle {
  const ThirdPartyLicenseBundle({
    required this.version,
    required this.items,
  });

  final String version;
  final List<ThirdPartyLicenseItem> items;
}

final thirdPartyLicensesProvider =
    FutureProvider.autoDispose<ThirdPartyLicenseBundle>((ref) async {
  final packageInfoFuture = PackageInfo.fromPlatform();
  final entriesFuture = LicenseRegistry.licenses.toList();
  final packageInfo = await packageInfoFuture;
  final entries = await entriesFuture;
  final grouped = <String, List<LicenseParagraph>>{};

  for (final entry in entries) {
    final paragraphs = entry.paragraphs.toList(growable: false);
    for (final package in entry.packages) {
      grouped
          .putIfAbsent(package, () => <LicenseParagraph>[])
          .addAll(paragraphs);
    }
  }

  final items = grouped.entries
      .map(
        (entry) => ThirdPartyLicenseItem(
          packageName: entry.key,
          paragraphs: List<LicenseParagraph>.unmodifiable(entry.value),
        ),
      )
      .toList()
    ..sort(
      (left, right) => left.packageName
          .toLowerCase()
          .compareTo(right.packageName.toLowerCase()),
    );

  return ThirdPartyLicenseBundle(
    version: '${packageInfo.version} (${packageInfo.buildNumber})',
    items: List<ThirdPartyLicenseItem>.unmodifiable(items),
  );
});

class ThirdPartyLicensesPage extends ConsumerWidget {
  const ThirdPartyLicensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenses = ref.watch(thirdPartyLicensesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('第三方库许可'),
        actions: <Widget>[
          IconButton(
            tooltip: '重新读取许可',
            onPressed: () => ref.invalidate(thirdPartyLicensesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: licenses.when(
        loading: () => const AppLoadingState(label: '正在读取第三方许可'),
        error: (_, __) => AppErrorState(
          title: '第三方许可读取失败',
          message: '无法读取应用随附的许可信息，请重试。',
          onRetry: () => ref.invalidate(thirdPartyLicensesProvider),
        ),
        data: (bundle) => AppPageList(
          children: <Widget>[
            AppSectionCard(
              title: '应用',
              addDividers: false,
              contentPadding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'MoFox Android',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '版本 ${bundle.version}\nReleased under AGPL-3.0',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppStatusBadge(
                  label: '${bundle.items.length} 个许可包',
                  tone: AppStatusTone.info,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (bundle.items.isEmpty)
              const AppEmptyState(
                title: '没有第三方许可条目',
                message: '当前构建未注册额外的第三方许可。',
                icon: Icons.gavel_outlined,
              )
            else
              AppSectionCard(
                title: '依赖许可',
                children: <Widget>[
                  for (final item in bundle.items)
                    AppSettingTile(
                      leading: const Icon(Icons.description_outlined),
                      title: item.packageName,
                      subtitle: '${item.paragraphs.length} 个许可段落',
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLicense(context, item),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLicense(
    BuildContext context,
    ThirdPartyLicenseItem item,
  ) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle:
          reduceMotion ? AnimationStyle.noAnimation : const AnimationStyle(),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AppAdaptiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        item.packageName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭许可详情',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SelectableText(item.text),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonalIcon(
                onPressed: () => _copyLicense(context, item.text),
                icon: const Icon(Icons.content_copy),
                label: const Text('复制许可文本'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyLicense(BuildContext context, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('许可文本已复制')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制许可文本失败')),
      );
    }
  }
}
