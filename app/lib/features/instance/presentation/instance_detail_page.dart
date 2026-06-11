import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../application/instance_repository.dart';
import '../domain/instance.dart';

class InstanceDetailPage extends ConsumerWidget {
  const InstanceDetailPage({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(instance.name),
        actions: <Widget>[
          IconButton(
            tooltip: '删除实例',
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.smart_toy_outlined,
                          color: scheme.onPrimaryContainer,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              instance.name,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'QQ ${instance.botQq}',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusPill(instance: instance),
                    ],
                  ),
                  if (instance.installError != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      instance.installError!,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '账号',
            rows: <_DetailRow>[
              _DetailRow('Bot QQ', instance.botQq),
              if (instance.botNickname.isNotEmpty)
                _DetailRow('Bot 昵称', instance.botNickname),
              _DetailRow('主人 QQ', instance.ownerQq),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '网络与组件',
            rows: <_DetailRow>[
              _DetailRow('WebSocket 端口', '${instance.wsPort}'),
              _DetailRow('更新通道', instance.channel),
              _DetailRow('WebUI 管理面板', instance.installWebui ? '已安装' : '未安装'),
              _DetailRow('NapCat', '全局共享'),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '路径',
            rows: <_DetailRow>[
              _DetailRow('实例目录', instance.installDir, copyable: true),
              _DetailRow('Bot 目录', instance.repoPath, copyable: true),
              _DetailRow('创建时间', _formatDateTime(instance.createdAt)),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed:
                    instance.installStatus == InstanceInstallStatus.installed
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('启动 Bot 待实现')),
                            );
                          }
                        : () => context.push(AppRoute.wizard, extra: instance),
                icon: Icon(
                  instance.installStatus == InstanceInstallStatus.installed
                      ? Icons.play_arrow
                      : Icons.download_done_outlined,
                ),
                label: Text(
                  instance.installStatus == InstanceInstallStatus.installed
                      ? '启动'
                      : '继续安装',
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.go(
                  AppRoute.terminal,
                  extra: <String, String>{
                    'cwd': instance.repoPath,
                    'title': '${instance.name} - Bot 目录',
                  },
                ),
                icon: const Icon(Icons.terminal),
                label: const Text('Bot 目录终端'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              foregroundColor: scheme.error,
            ),
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除实例'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除实例？'),
        content: Text('将删除 ${instance.name} 的本地记录和实例目录。此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final runtime = ref.read(runtimeBridgeProvider);
      final result = await runtime.runInstallTask(
        'deleteInstance',
        args: <String, String>{'installDir': instance.installDir},
      );
      if (!result.success) {
        throw StateError(result.error ?? '删除实例目录失败');
      }
      final repo = await ref.read(instanceRepositoryProvider.future);
      await repo.remove(instance.id);
      ref.invalidate(instancesProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('实例已删除')));
      context.go(AppRoute.dashboard);
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(instance, scheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(instance),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _statusTextColor(instance, scheme),
            ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.rows});

  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              _DetailTile(row: row, valueColor: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value, {this.copyable = false});

  final String label;
  final String value;
  final bool copyable;
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.row, required this.valueColor});

  final _DetailRow row;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(
              row.label,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              row.value.isEmpty ? '（未填写）' : row.value,
              style: text.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
          if (row.copyable)
            IconButton(
              tooltip: '复制',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: row.value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
            ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _statusLabel(Instance instance) {
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => '未完成',
    InstanceInstallStatus.failed => '安装失败',
    InstanceInstallStatus.installed => '已停止',
  };
}

Color _statusColor(Instance instance, ColorScheme scheme) {
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => scheme.tertiaryContainer,
    InstanceInstallStatus.failed => scheme.errorContainer,
    InstanceInstallStatus.installed => scheme.surfaceContainerHigh,
  };
}

Color _statusTextColor(Instance instance, ColorScheme scheme) {
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => scheme.onTertiaryContainer,
    InstanceInstallStatus.failed => scheme.onErrorContainer,
    InstanceInstallStatus.installed => scheme.onSurfaceVariant,
  };
}
