import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/security/webui_key_store.dart';
import '../../../core/ui/explosion_overlay.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';
import '../../wizard/application/wizard_notifier.dart';
import '../application/process_console_provider.dart';

/// 管理页：实例卡片网格 + 新建 CTA。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final asyncInstances = ref.watch(instancesProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(instancesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewWizard(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('创建实例'),
      ),
      body: SafeArea(
        child: asyncInstances.when(
          loading: () => _DashboardBody(
            items: const <Instance>[],
            instancesLoading: true,
          ),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (items) => _DashboardBody(items: items),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.items,
    this.instancesLoading = false,
  });

  final List<Instance> items;
  final bool instancesLoading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 720 ? 24.0 : 16.0;
        return CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                12,
              ),
              sliver: const SliverToBoxAdapter(child: _SectionHeader()),
            ),
            if (instancesLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              _InstanceGrid(
                items: items,
                horizontalPadding: horizontalPadding,
              ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Text(
      '实例',
      style: text.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 48,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有 Bot 实例',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击右下角 “创建实例” 通过向导部署你的第一个 MoFox Bot。',
              style: text.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openNewWizard(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('创建第一个实例'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstanceGrid extends StatelessWidget {
  const _InstanceGrid({required this.items, required this.horizontalPadding});
  final List<Instance> items;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent - horizontalPadding * 2;
        final crossAxis = width >= 720 ? 2 : 1;
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            96,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxis,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 224,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _InstanceCard(instance: items[i]),
          ),
        );
      },
    );
  }
}

class _InstanceCard extends ConsumerStatefulWidget {
  const _InstanceCard({required this.instance});
  final Instance instance;

  @override
  ConsumerState<_InstanceCard> createState() => _InstanceCardState();
}

class _InstanceCardState extends ConsumerState<_InstanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _removeController;

  final GlobalKey cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _removeController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _removeController.dispose();
    super.dispose();
  }

  /// 触发爆炸动画 + 震动，动画结束后执行真正的删除逻辑。
  Future<void> _animateAndDelete() async {
    final renderBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) {
      // 无法获取位置，直接删除
      _confirmDeleteInstance(context, ref, widget.instance);
      return;
    }

    final cardRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final scheme = Theme.of(context).colorScheme;

    // 震动反馈
    HapticFeedback.heavyImpact();

    // 粒子爆炸 overlay
    ExplosionOverlay.show(
      context,
      rect: cardRect,
      color: scheme.primary,
    );

    // 卡片缩小消失动画
    await _removeController.forward();

    if (!mounted) return;
    _confirmDeleteInstance(context, ref, widget.instance);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final instance = widget.instance;
    // 监听运行时进程状态，已安装实例若 bot 在跑则显示"运行中"
    final botStatus = ref.watch(processConsoleProvider).botStatus;

    return AnimatedBuilder(
      animation: _removeController,
      builder: (_, child) {
        final t = _removeController.value;
        return Opacity(
          opacity: 1 - t,
          child: Transform.scale(
            scale: 1 - t * 0.3,
            child: child,
          ),
        );
      },
      child: Material(
        key: cardKey,
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoute.instanceDetail, extra: instance),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
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
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'QQ ${instance.botQq}',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(instance, scheme, botStatus),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(instance, botStatus),
                        style: text.labelSmall?.copyWith(
                          color: _statusTextColor(instance, scheme, botStatus),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除实例',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('删除实例？'),
                            content: Text(
                              '将删除 ${instance.name} 的本地记录和实例目录。此操作无法撤销。',
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          _animateAndDelete();
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const Spacer(),
                if (instance.installStatus != InstanceInstallStatus.installed &&
                    instance.installError != null) ...<Widget>[
                  Text(
                    instance.installError!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: <Widget>[
                    _MetaItem(
                      icon: Icons.cloud_outlined,
                      label: 'WS :${instance.wsPort}',
                    ),
                    _MetaItem(
                      icon: Icons.flag_outlined,
                      label: instance.channel,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      IconButton.filledTonal(
                        tooltip: '在 Bot 目录打开终端',
                        onPressed: () => context.push(
                          AppRoute.terminal,
                          extra: <String, String>{
                            'cwd': instance.repoPath,
                            'title': '${instance.name} - Bot 目录',
                          },
                        ),
                        icon: const Icon(Icons.terminal, size: 18),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: instance.installStatus ==
                                InstanceInstallStatus.installed
                            ? () => context.push(
                                  AppRoute.instanceDetail,
                                  extra: instance,
                                )
                            : () =>
                                context.push(AppRoute.wizard, extra: instance),
                        icon: Icon(
                          instance.installStatus ==
                                  InstanceInstallStatus.installed
                              ? Icons.play_arrow
                              : Icons.download_done_outlined,
                          size: 18,
                        ),
                        label: Text(
                          instance.installStatus ==
                                  InstanceInstallStatus.installed
                              ? '启动'
                              : '继续安装',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openNewWizard(BuildContext context, WidgetRef ref) {
  ref.read(wizardProvider.notifier).resetForNewInstance();
  context.push(AppRoute.wizard);
}

Future<void> _confirmDeleteInstance(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    // 先删除本地记录并刷新 UI，确保实例立即从列表消失。
    final repo = await ref.read(instanceRepositoryProvider.future);
    await repo.remove(instance.id);
    ref.invalidate(instancesProvider);
    // 清理安全存储中的 WebUI api_key
    await WebuiKeyStore.delete(instance.id);

    // 再尝试删除 rootfs 中的实例目录；失败只警告，不阻止本地记录删除。
    try {
      final runtime = ref.read(runtimeBridgeProvider);
      final result = await runtime.runInstallTask(
        'deleteInstance',
        args: <String, String>{'installDir': instance.installDir},
      );
      if (!result.success && context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('本地记录已删除，远程目录清理失败：${result.error ?? "未知错误"}')),
        );
        return;
      }
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('本地记录已删除，远程目录清理异常：$error')),
      );
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('实例已删除')));
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

String _statusLabel(Instance instance, String botStatus) {
  if (instance.installStatus == InstanceInstallStatus.installed &&
      botStatus == 'running') {
    return '运行中';
  }
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => '未完成',
    InstanceInstallStatus.failed => '安装失败',
    InstanceInstallStatus.installed => '已停止',
  };
}

Color _statusColor(Instance instance, ColorScheme scheme, String botStatus) {
  if (instance.installStatus == InstanceInstallStatus.installed &&
      botStatus == 'running') {
    return scheme.primaryContainer;
  }
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => scheme.tertiaryContainer,
    InstanceInstallStatus.failed => scheme.errorContainer,
    InstanceInstallStatus.installed => scheme.surfaceContainerHigh,
  };
}

Color _statusTextColor(
    Instance instance, ColorScheme scheme, String botStatus) {
  if (instance.installStatus == InstanceInstallStatus.installed &&
      botStatus == 'running') {
    return scheme.onPrimaryContainer;
  }
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => scheme.onTertiaryContainer,
    InstanceInstallStatus.failed => scheme.onErrorContainer,
    InstanceInstallStatus.installed => scheme.onSurfaceVariant,
  };
}
