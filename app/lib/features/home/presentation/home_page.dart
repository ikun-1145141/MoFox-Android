import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../dashboard/application/system_stats_provider.dart';
import '../../dashboard/domain/system_stats.dart';
import '../../settings/application/app_settings_provider.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(systemStatsProvider);
    final mainImageMode =
        ref.watch(appSettingsProvider).valueOrNull?.mainImageMode ??
            MainImageMode.expressive;

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
            onPressed: () => ref.invalidate(systemStatsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 720 ? 24.0 : 16.0;
            return CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    96,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _SystemOverview(
                      stats: stats,
                      mainImageMode: mainImageMode,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SystemOverview extends StatelessWidget {
  const _SystemOverview({required this.stats, required this.mainImageMode});

  final AsyncValue<SystemStats> stats;
  final MainImageMode mainImageMode;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const _SystemOverviewSkeleton(),
      error: (error, _) => _SystemErrorCard(error: error),
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (mainImageMode != MainImageMode.hidden) ...<Widget>[
            _HomeHero(stats: value, mode: mainImageMode),
            const SizedBox(height: 12),
          ],
          _LoadCard(stats: value),
          const SizedBox(height: 12),
          _DeviceDetailsCard(stats: value),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.stats, required this.mode});

  final SystemStats stats;
  final MainImageMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final compact = mode == MainImageMode.compact;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stats.deviceName.isEmpty ? 'MoFox Runtime' : stats.deviceName,
                  style: (compact ? text.titleLarge : text.headlineSmall)
                      ?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: compact ? 6 : 10),
                Text(
                  'Android ${stats.androidVersion} · ${stats.supportedAbis}',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withOpacity(0.78),
                  ),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: compact ? 44 : 60,
            height: compact ? 44 : 60,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: scheme.onPrimaryContainer,
              size: compact ? 24 : 30,
            ),
          ),
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
                  '资源占用',
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
                          (tile) => <Widget>[tile, const SizedBox(width: 12)],
                        )
                        .toList()
                      ..removeLast(),
                  );
                }
                return Column(
                  children: tiles
                      .expand(
                        (tile) => <Widget>[tile, const SizedBox(height: 12)],
                      )
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
      _DetailItem('SoC', stats.socName),
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

class _DetailItem {
  const _DetailItem(this.label, this.value);

  final String label;
  final String value;
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
