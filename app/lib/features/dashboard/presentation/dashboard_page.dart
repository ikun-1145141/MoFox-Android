import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../application/system_stats_provider.dart';
import '../domain/system_stats.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';

/// 首页：机器状态总览 + 实例卡片网格 + 新建 CTA。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final asyncInstances = ref.watch(instancesProvider);
    final asyncStats = ref.watch(systemStatsProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('首页'),
        actions: <Widget>[
          IconButton(
            tooltip: '打开终端',
            onPressed: () => context.push(
              AppRoute.terminal,
              extra: <String, String>{'cwd': '/root', 'title': '终端'},
            ),
            icon: const Icon(Icons.terminal),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(systemStatsProvider);
              ref.invalidate(instancesProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoute.wizard),
        icon: const Icon(Icons.add),
        label: const Text('创建实例'),
      ),
      body: SafeArea(
        child: asyncInstances.when(
          loading: () => _DashboardBody(
            stats: asyncStats,
            items: const <Instance>[],
            instancesLoading: true,
          ),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (items) => _DashboardBody(stats: asyncStats, items: items),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.stats,
    required this.items,
    this.instancesLoading = false,
  });

  final AsyncValue<SystemStats> stats;
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
              sliver: SliverToBoxAdapter(child: _SystemOverview(stats: stats)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
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
                  hasScrollBody: false, child: _EmptyState())
            else
              _InstanceGrid(items: items, horizontalPadding: horizontalPadding),
          ],
        );
      },
    );
  }
}

class _SystemOverview extends StatelessWidget {
  const _SystemOverview({required this.stats});

  final AsyncValue<SystemStats> stats;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const _SystemOverviewSkeleton(),
      error: (error, _) => _SystemErrorCard(error: error),
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LoadCard(stats: value),
          const SizedBox(height: 12),
          _DeviceDetailsCard(stats: value),
        ],
      ),
    );
  }
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.stats});

  final SystemStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
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
                Icon(Icons.monitor_heart_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '机器负载',
                  style: text.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 640;
                final tiles = <Widget>[
                  _UsageTile(
                    icon: Icons.memory_outlined,
                    label: 'CPU',
                    value: _formatPercent(stats.cpuUsage),
                    detail: '${stats.cpuCores} 核心',
                    usage: stats.cpuUsage,
                  ),
                  _UsageTile(
                    icon: Icons.sd_card_outlined,
                    label: '内存',
                    value: _formatPercent(stats.memoryUsage),
                    detail:
                        '${_formatBytes(stats.memoryUsed)} / ${_formatBytes(stats.memoryTotal)}',
                    usage: stats.memoryUsage,
                  ),
                  _UsageTile(
                    icon: Icons.storage_outlined,
                    label: '存储',
                    value: _formatPercent(stats.storageUsage),
                    detail:
                        '${_formatBytes(stats.storageUsed)} / ${_formatBytes(stats.storageTotal)}',
                    usage: stats.storageUsage,
                  ),
                ];
                if (wide) {
                  return Row(
                    children: tiles
                        .map((tile) => Expanded(child: tile))
                        .expand(
                            (tile) => <Widget>[tile, const SizedBox(width: 12)])
                        .toList()
                      ..removeLast(),
                  );
                }
                return Column(
                  children: tiles
                      .expand(
                          (tile) => <Widget>[tile, const SizedBox(height: 12)])
                      .toList()
                    ..removeLast(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageTile extends StatelessWidget {
  const _UsageTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.usage,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final double usage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: text.labelLarge?.copyWith(color: scheme.onSurface),
                ),
              ),
              Text(
                value,
                style: text.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: usage,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DeviceDetailsCard extends StatelessWidget {
  const _DeviceDetailsCard({required this.stats});

  final SystemStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final items = <_DetailItem>[
      _DetailItem('设备', stats.deviceName),
      _DetailItem(
          '系统', 'Android ${stats.androidVersion} (SDK ${stats.sdkInt})'),
      _DetailItem('架构', stats.supportedAbis),
      _DetailItem('内核', stats.kernel),
      _DetailItem('Rootfs', stats.rootfsPath),
      _DetailItem('应用数据', stats.appDataPath),
    ];
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
                Icon(Icons.phone_android_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '机器配置',
                  style: text.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) => _DetailRow(item: item)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.item});

  final _DetailItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              item.label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              item.value.isEmpty ? '-' : item.value,
              style: text.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemOverviewSkeleton extends StatelessWidget {
  const _SystemOverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: const SizedBox(
        height: 176,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _SystemErrorCard extends StatelessWidget {
  const _SystemErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '机器状态读取失败：$error',
                style:
                    text.bodyMedium?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
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

class _DetailItem {
  const _DetailItem(this.label, this.value);

  final String label;
  final String value;
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
              onPressed: () => GoRouter.of(context).go(AppRoute.wizard),
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

String _formatPercent(double value) => '${(value * 100).round()}%';

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = size >= 10 || unit == 0 ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
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
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '已停止',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('启动 Bot 待实现')),
                      );
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('启动'),
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
