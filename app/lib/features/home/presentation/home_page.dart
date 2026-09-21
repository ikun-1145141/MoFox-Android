import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_components.dart';
import '../../dashboard/application/process_console_provider.dart';
import '../../dashboard/application/system_stats_provider.dart';
import '../../dashboard/domain/system_stats.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';
import '../../settings/application/app_settings_provider.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(systemStatsProvider);
    final instances = ref.watch(instancesProvider);
    final activeInstanceId = ref.watch(
      processConsoleProvider.select((state) => state.activeInstanceId),
    );
    final botStatus = ref.watch(
      processConsoleProvider.select((state) => state.botStatus),
    );
    final napcatStatus = ref.watch(
      processConsoleProvider.select((state) => state.napcatStatus),
    );
    final busyAction = ref.watch(
      processConsoleProvider.select((state) => state.busyAction),
    );
    final mainImageMode =
        ref.watch(appSettingsProvider).valueOrNull?.mainImageMode ??
            MainImageMode.expressive;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('概览'),
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
              ref
                ..invalidate(systemStatsProvider)
                ..invalidate(instancesProvider);
              ref.read(processConsoleProvider.notifier).refreshStatus();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppPageList(
        maxWidth: 960,
        children: <Widget>[
          _InstanceOverview(
            instances: instances,
            activeInstanceId: activeInstanceId,
            botStatus: botStatus,
            napcatStatus: napcatStatus,
            busyAction: busyAction,
            onRetry: () => ref.invalidate(instancesProvider),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SystemOverview(
            stats: stats,
            mainImageMode: mainImageMode,
            onRetry: () => ref.invalidate(systemStatsProvider),
          ),
        ],
      ),
    );
  }
}

class _InstanceOverview extends StatelessWidget {
  const _InstanceOverview({
    required this.instances,
    required this.activeInstanceId,
    required this.botStatus,
    required this.napcatStatus,
    required this.busyAction,
    required this.onRetry,
  });

  final AsyncValue<List<Instance>> instances;
  final String? activeInstanceId;
  final String botStatus;
  final String napcatStatus;
  final String? busyAction;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return instances.when(
      loading: () => const AppSectionCard(
        title: '运行概览',
        addDividers: false,
        children: <Widget>[
          AppLoadingState(label: '正在读取实例'),
        ],
      ),
      error: (_, __) => AppSectionCard(
        title: '运行概览',
        addDividers: false,
        children: <Widget>[
          AppErrorState(
            title: '无法读取实例',
            message: '本地实例列表加载失败，请重试。',
            onRetry: onRetry,
          ),
        ],
      ),
      data: (items) => _buildData(context, items),
    );
  }

  Widget _buildData(BuildContext context, List<Instance> items) {
    if (items.isEmpty) {
      return AppSectionCard(
        title: '运行概览',
        addDividers: false,
        children: <Widget>[
          AppEmptyState(
            icon: Icons.smart_toy_outlined,
            title: '还没有 Bot 实例',
            message: '创建实例后，这里会显示实时运行状态。',
            action: FilledButton.icon(
              onPressed: () => context.go(AppRoute.dashboard),
              icon: const Icon(Icons.add),
              label: const Text('创建实例'),
            ),
          ),
        ],
      );
    }

    Instance? active;
    for (final item in items) {
      if (item.id == activeInstanceId) {
        active = item;
        break;
      }
    }
    final hasRunningProcess =
        botStatus == 'running' || napcatStatus == 'running';
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppSectionCard(
      title: '运行概览',
      addDividers: false,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: ShapeDecoration(
                      color: active == null
                          ? scheme.surfaceContainerHighest
                          : scheme.primaryContainer,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppRadii.control),
                        ),
                      ),
                    ),
                    child: Icon(
                      active == null
                          ? Icons.pause_rounded
                          : Icons.smart_toy_rounded,
                      color: active == null
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          active?.name ??
                              (hasRunningProcess ? '运行实例待确认' : '当前没有运行实例'),
                          style: textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          active == null
                              ? '共 ${items.length} 个实例'
                              : '${active.botQq} · ${active.channel == 'main' ? '稳定版' : '开发版'}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  if (busyAction != null)
                    const AppStatusBadge(
                      label: '正在执行操作',
                      tone: AppStatusTone.info,
                      icon: Icons.sync,
                    )
                  else if (active == null && hasRunningProcess)
                    const AppStatusBadge(
                      label: '检测到运行进程，实例待确认',
                      tone: AppStatusTone.warning,
                    )
                  else ...<Widget>[
                    _processBadge('Bot', botStatus, active != null),
                    _processBadge('NapCat', napcatStatus, active != null),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () => context.go(AppRoute.dashboard),
                    icon: const Icon(Icons.dashboard_outlined),
                    label: const Text('查看全部实例'),
                  ),
                  if (active != null)
                    OutlinedButton.icon(
                      onPressed: () => context.push(
                        AppRoute.instanceDetail,
                        extra: active,
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('管理当前实例'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  AppStatusBadge _processBadge(
    String name,
    String status,
    bool belongsToActiveInstance,
  ) {
    if (!belongsToActiveInstance) {
      return AppStatusBadge(
        label: '$name 已停止',
        tone: AppStatusTone.neutral,
      );
    }
    return switch (status) {
      'running' => AppStatusBadge(
          label: '$name 运行中',
          tone: AppStatusTone.success,
        ),
      'starting' || 'stopping' => AppStatusBadge(
          label: '$name 切换中',
          tone: AppStatusTone.info,
          icon: Icons.sync,
        ),
      'failed' => AppStatusBadge(
          label: '$name 异常',
          tone: AppStatusTone.error,
        ),
      _ => AppStatusBadge(
          label: '$name 已停止',
          tone: AppStatusTone.neutral,
        ),
    };
  }
}

class _SystemOverview extends StatelessWidget {
  const _SystemOverview({
    required this.stats,
    required this.mainImageMode,
    required this.onRetry,
  });

  final AsyncValue<SystemStats> stats;
  final MainImageMode mainImageMode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const AppLoadingState(label: '正在读取设备状态'),
      error: (_, __) => AppErrorState(
        title: '无法读取设备状态',
        message: '请检查系统权限或稍后重试。',
        onRetry: onRetry,
      ),
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (mainImageMode != MainImageMode.hidden) ...<Widget>[
            _HomeHero(stats: value, mode: mainImageMode),
            const SizedBox(height: AppSpacing.xl),
          ],
          _LoadCard(stats: value),
          const SizedBox(height: AppSpacing.xl),
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedContainer(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: ShapeDecoration(
        color: scheme.primaryContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppRadii.card),
          ),
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
                    color: scheme.onPrimaryContainer,
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
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: scheme.onPrimary,
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
    return AppSectionCard(
      title: '资源占用',
      addDividers: false,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
      ],
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
          Semantics(
            label: '$label使用率',
            value: value,
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
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
    return AppSectionCard(
      title: '设备信息',
      addDividers: false,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ...items.map((item) => _DetailRow(item: item)),
            ],
          ),
        ),
      ],
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
