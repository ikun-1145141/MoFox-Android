import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/troubleshooting/application/error_report_provider.dart';

/// 报错汇总：本次启动的全部报错与关键诊断行。
///
/// 目标使用方式是用户直接截图/复制发给 AI 排查，因此正文用等宽字体、
/// 每行带时间与来源前缀、整页可选中，并提供「复制全部」（带设备头）。
class ErrorReportPage extends ConsumerWidget {
  const ErrorReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(errorReportProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('报错汇总'),
        actions: <Widget>[
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: entries.isEmpty ? null : () => _copyAll(context, ref),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: entries.isEmpty ? null : () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const AppEmptyState(
              title: '本次启动没有报错记录',
              message: '出现异常时，报错与关键诊断行会自动汇总到这里',
              icon: Icons.verified_outlined,
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.privacy_tip_outlined,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '内容已自动打码 token 等密钥；发给 AI 前请再确认无敏感信息。复制全文比截图更精准。',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SelectionArea(
                    child: ListView.separated(
                      // 最新在前：截图时最近发生的问题直接可见。
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _EntryTile(entry: entries[entries.length - 1 - index]),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _copyAll(BuildContext context, WidgetRef ref) async {
    final text = await ref.read(errorReportProvider.notifier).buildExportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制报错汇总，可粘贴给 AI 排查')),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空报错汇总？'),
        content: const Text('将删除本次启动记录的全部报错与诊断行。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      ref.read(errorReportProvider.notifier).clear();
    }
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final ErrorReportEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final messageColor = switch (entry.level) {
      ErrorReportLevel.error => scheme.error,
      ErrorReportLevel.warning => scheme.tertiary,
      ErrorReportLevel.diag => scheme.onSurface,
    };
    final levelIcon = switch (entry.level) {
      ErrorReportLevel.error => Icons.error_outline,
      ErrorReportLevel.warning => Icons.warning_amber_rounded,
      ErrorReportLevel.diag => Icons.terminal,
    };
    final meta = <String>[
      ErrorReportNotifier.formatTime(entry.time),
      entry.source,
      if (entry.repeat > 1) '×${entry.repeat}',
    ].join(' · ');
    return ListTile(
      dense: true,
      leading: Icon(levelIcon, size: 20, color: messageColor),
      title: Text(
        entry.message,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.35,
          color: messageColor,
        ),
      ),
      subtitle: Text(
        meta,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
