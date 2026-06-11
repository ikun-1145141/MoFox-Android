import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';

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
        onPressed: () => context.push(AppRoute.wizard),
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
              _InstanceGrid(items: items, horizontalPadding: horizontalPadding),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => GoRouter.of(context).push(AppRoute.wizard),
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
              mainAxisExtent: 204,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _InstanceCard(instance: items[i]),
          ),
        );
      },
    );
  }
}

class _InstanceCard extends StatelessWidget {
  const _InstanceCard({required this.instance});
  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('实例详情待实现')),
          );
        },
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
                      color: _statusColor(instance, scheme),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(instance),
                      style: text.labelSmall?.copyWith(
                        color: _statusTextColor(instance, scheme),
                      ),
                    ),
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
              Row(
                children: <Widget>[
                  Icon(
                    Icons.cloud_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'WS :${instance.wsPort}',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    instance.channel,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
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
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: '在实例根目录打开终端',
                    onPressed: () => context.push(
                      AppRoute.terminal,
                      extra: <String, String>{
                        'cwd': instance.installDir,
                        'title': '${instance.name} - 实例目录',
                      },
                    ),
                    icon: const Icon(Icons.folder_open, size: 18),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: instance.installStatus ==
                            InstanceInstallStatus.installed
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
                      size: 18,
                    ),
                    label: Text(
                      instance.installStatus == InstanceInstallStatus.installed
                          ? '启动'
                          : '继续安装',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
