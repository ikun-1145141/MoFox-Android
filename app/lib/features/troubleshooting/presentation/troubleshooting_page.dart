import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mofox_android/app/router/app_router.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/troubleshooting/domain/troubleshooting_entry.dart';

/// 常见问题：自助排查手册 + 引导到报错汇总截图问 AI。
class TroubleshootingPage extends ConsumerWidget {
  const TroubleshootingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('常见问题')),
      body: AppPageList(
        children: <Widget>[
          AppSectionCard(
            title: '快速自查',
            children: <Widget>[
              AppSettingTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: '报错汇总',
                subtitle: '把本次启动的报错截图或复制发给 AI 帮你定位',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoute.errorReport),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionCard(
            title: '常见问题',
            children: <Widget>[
              for (final entry in troubleshootingEntries)
                _EntryCard(entry: entry),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final TroubleshootingEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(entry.title, style: text.bodyLarge),
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '可能的原因',
            style: text.labelLarge?.copyWith(color: scheme.primary),
          ),
        ),
        const SizedBox(height: 4),
        for (final cause in entry.causes)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '· $cause',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '解决步骤',
            style: text.labelLarge?.copyWith(color: scheme.primary),
          ),
        ),
        const SizedBox(height: 4),
        for (final (index, step) in entry.steps.indexed)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${index + 1}. $step',
              style: text.bodyMedium,
            ),
          ),
        if (entry.jump != null) ...<Widget>[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => context.push(entry.jump!.route),
              icon: const Icon(Icons.arrow_outward),
              label: Text(entry.jump!.label),
            ),
          ),
        ],
      ],
    );
  }
}
