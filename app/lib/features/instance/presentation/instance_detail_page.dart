import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/ui/ansi_color_text.dart';
import '../../dashboard/application/process_console_provider.dart';
import '../application/instance_repository.dart';
import '../domain/instance.dart';
import '../../wizard/presentation/widgets/napcat_qr_sheet.dart';

class InstanceDetailPage extends ConsumerStatefulWidget {
  const InstanceDetailPage({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<InstanceDetailPage> createState() => _InstanceDetailPageState();
}

class _InstanceDetailPageState extends ConsumerState<InstanceDetailPage> {
  bool _qrShown = false;

  Instance get instance => widget.instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final console = ref.watch(processConsoleProvider);
    final installed = instance.installStatus == InstanceInstallStatus.installed;

    ref.listen<ProcessConsoleState>(processConsoleProvider, (prev, next) {
      if (next.napcatQrPayload != null && !_qrShown) {
        _qrShown = true;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => NapcatQrSheet(payload: next.napcatQrPayload!),
        ).whenComplete(() => _qrShown = false);
      } else if (next.napcatQrPayload == null && _qrShown) {
        Navigator.of(context).pop();
        _qrShown = false;
      }
    });

    return Scaffold(
      body: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: <Widget>[
              Material(
                color: scheme.surfaceContainerLow,
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconButton(
                            tooltip: '返回',
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.smart_toy_outlined,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  instance.name,
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: <Widget>[
                                    _LiveDot(status: console.botStatus),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        installed
                                            ? 'Bot ${_processStatusLabel(console.botStatus)} · NapCat ${_processStatusLabel(console.napcatStatus)}'
                                            : _statusLabel(instance),
                                        style: text.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Bot 目录终端',
                            onPressed: () => context.go(
                              AppRoute.terminal,
                              extra: <String, String>{
                                'cwd': instance.repoPath,
                                'title': '${instance.name} - Bot 目录',
                              },
                            ),
                            icon: const Icon(Icons.terminal),
                          ),
                          IconButton(
                            tooltip: '实例信息',
                            onPressed: () => _showInstanceInfoSheet(context),
                            icon: const Icon(Icons.info_outline),
                          ),
                          IconButton(
                            tooltip: '删除实例',
                            onPressed: () => _confirmDelete(context, ref),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: !installed || console.isBusy
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .startBot(instance),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('启动'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: !installed || console.isBusy
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .stopBot(),
                              icon: const Icon(Icons.stop),
                              label: const Text('停止'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: !installed || console.isBusy
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .restartBot(instance),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('重启'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !installed || console.isBusy
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .startNapcat(instance),
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('NapCat'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !installed || console.isBusy
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .stopNapcat(),
                              icon: const Icon(Icons.stop),
                              label: const Text('停止'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !installed || console.isBusy
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .restartNapcat(instance),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('重启'),
                            ),
                          ),
                        ],
                      ),
                      if (console.errorMessage != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            console.errorMessage!,
                            style:
                                text.bodySmall?.copyWith(color: scheme.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              TabBar(
                tabs: const <Widget>[
                  Tab(icon: Icon(Icons.terminal), text: 'Bot 主程序'),
                  Tab(icon: Icon(Icons.qr_code_2), text: 'NapCat'),
                ],
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _ProcessLogPane(lines: console.botLogs),
                    _ProcessLogPane(lines: console.napcatLogs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInstanceInfoSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.smart_toy_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                  _DetailRow(
                      'WebUI 管理面板', instance.installWebui ? '已安装' : '未安装'),
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
              if (instance.installStatus != InstanceInstallStatus.installed)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.push(AppRoute.wizard, extra: instance);
                  },
                  icon: const Icon(Icons.download_done_outlined),
                  label: const Text('继续安装'),
                ),
            ],
          ),
        ),
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
      // 先删除本地记录并刷新 UI，确保实例立即从列表消失。
      final repo = await ref.read(instanceRepositoryProvider.future);
      await repo.remove(instance.id);
      ref.invalidate(instancesProvider);

      // 再尝试删除 rootfs 中的实例目录；失败只警告，不阻止本地记录删除。
      try {
        final runtime = ref.read(runtimeBridgeProvider);
        final result = await runtime.runInstallTask(
          'deleteInstance',
          args: <String, String>{'installDir': instance.installDir},
        );
        if (!result.success && context.mounted) {
          messenger.showSnackBar(
            SnackBar(
                content: Text('本地记录已删除，远程目录清理失败：${result.error ?? "未知错误"}')),
          );
          context.go(AppRoute.dashboard);
          return;
        }
      } catch (error) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('本地记录已删除，远程目录清理异常：$error')),
        );
        context.go(AppRoute.dashboard);
        return;
      }
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('实例已删除')));
      context.go(AppRoute.dashboard);
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = status == 'running';
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: running ? Colors.green : scheme.outline,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ProcessLogPane extends StatelessWidget {
  const _ProcessLogPane({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.35,
        );
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(12),
      child: lines.isEmpty
          ? Text(
              '暂无日志',
              style: style?.copyWith(color: scheme.outlineVariant),
            )
          : ListView.builder(
              itemCount: lines.length,
              itemBuilder: (context, index) => AnsiColorText(
                lines[index],
                style: style,
              ),
            ),
    );
  }
}

String _processStatusLabel(String status) {
  return status == 'running' ? 'Bot 运行中' : 'Bot 已停止';
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
