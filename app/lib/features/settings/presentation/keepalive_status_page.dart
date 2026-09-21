import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mofox_android/core/platform/platform_gateway.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:permission_handler/permission_handler.dart';

final keepaliveStatusProvider = FutureProvider.autoDispose<KeepaliveStatus>(
  (ref) => ref.watch(platformGatewayProvider).getKeepaliveStatus(),
);

class KeepaliveStatusPage extends ConsumerWidget {
  const KeepaliveStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(keepaliveStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('保活状态'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新保活状态',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(keepaliveStatusProvider),
          ),
        ],
      ),
      body: status.when(
        loading: () => const AppLoadingState(label: '正在读取保活状态'),
        error: (_, __) => AppErrorState(
          title: '保活状态读取失败',
          message: '无法读取系统权限和服务状态，请重试。',
          onRetry: () => ref.invalidate(keepaliveStatusProvider),
        ),
        data: (value) => RefreshIndicator(
          onRefresh: () async => ref.refresh(keepaliveStatusProvider.future),
          child: AppPageList(
            children: <Widget>[
              _StatusSummary(status: value),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '权限与服务',
                children: <Widget>[
                  _KeepaliveItem(
                    icon: Icons.notifications_active_outlined,
                    title: '通知权限',
                    description: '前台保活服务需要显示常驻通知。',
                    status: value.notificationsGranted ? '已授权' : '未授权',
                    tone: value.notificationsGranted
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                    actionLabel: value.notificationsGranted ? null : '去授权',
                    onPressed: value.notificationsGranted
                        ? null
                        : () => _requestNotification(context, ref),
                  ),
                  _KeepaliveItem(
                    icon: Icons.battery_charging_full_outlined,
                    title: '忽略电池优化',
                    description: '允许 MoFox 在后台更稳定地运行 Bot。',
                    status: value.ignoringBatteryOptimizations ? '已加入' : '待设置',
                    tone: value.ignoringBatteryOptimizations
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                    actionLabel:
                        value.ignoringBatteryOptimizations ? null : '去设置',
                    onPressed: value.ignoringBatteryOptimizations
                        ? null
                        : () => _requestBatteryOptimization(context, ref),
                  ),
                  _KeepaliveItem(
                    icon: Icons.sync_lock_outlined,
                    title: '前台保活服务',
                    description: '开启后 MoFox 会保留一个守护通知。',
                    status: value.foregroundServiceEnabled ? '运行中' : '已关闭',
                    tone: value.foregroundServiceEnabled
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                    actionLabel: value.foregroundServiceEnabled ? '关闭' : '开启',
                    onPressed: () => _toggleForegroundService(
                      context,
                      ref,
                      enabled: value.foregroundServiceEnabled,
                    ),
                  ),
                  _KeepaliveItem(
                    icon: Icons.restart_alt_outlined,
                    title: '开机自启声明',
                    description: '应用已声明开机广播接收器，实际触发受系统策略限制。',
                    status: value.bootReceiverDeclared ? '已声明' : '未声明',
                    tone: value.bootReceiverDeclared
                        ? AppStatusTone.success
                        : AppStatusTone.error,
                  ),
                  _KeepaliveItem(
                    icon: Icons.lock_outline,
                    title: '厂商自启动 / 最近任务锁定',
                    description: 'Android 没有统一查询接口，需要在系统页确认。',
                    status:
                        value.vendorAutostartInspectable ? '可自动检查' : '需手动确认',
                    tone: value.vendorAutostartInspectable
                        ? AppStatusTone.info
                        : AppStatusTone.warning,
                    actionLabel: '打开设置',
                    onPressed: () => _openVendorSettings(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final permission = await Permission.notification.request();
      if (!context.mounted) return;
      if (permission.isGranted) {
        await ref.read(platformGatewayProvider).startForegroundService();
        ref.invalidate(keepaliveStatusProvider);
        if (!context.mounted) return;
        _showSnack(context, '通知权限已开启，前台保活服务已启动');
        return;
      }
      if (permission.isPermanentlyDenied) await openAppSettings();
      ref.invalidate(keepaliveStatusProvider);
      if (!context.mounted) return;
      _showSnack(context, '请允许通知权限，否则前台保活服务无法稳定运行');
    } on Object {
      if (!context.mounted) return;
      _showSnack(context, '请求通知权限失败，请稍后重试');
    }
  }

  Future<void> _requestBatteryOptimization(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final granted = await ref
          .read(platformGatewayProvider)
          .requestIgnoreBatteryOptimizations();
      ref.invalidate(keepaliveStatusProvider);
      if (!context.mounted) return;
      _showSnack(context, granted ? '已在电池优化白名单中' : '已打开电池优化授权页');
    } on Object {
      if (!context.mounted) return;
      _showSnack(context, '无法打开电池优化设置');
    }
  }

  Future<void> _toggleForegroundService(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    try {
      final platform = ref.read(platformGatewayProvider);
      if (enabled) {
        await platform.stopForegroundService();
      } else {
        final permission = await Permission.notification.request();
        if (!permission.isGranted) {
          ref.invalidate(keepaliveStatusProvider);
          if (!context.mounted) return;
          _showSnack(context, '请先允许通知权限');
          return;
        }
        await platform.startForegroundService();
      }
      ref.invalidate(keepaliveStatusProvider);
    } on Object {
      if (!context.mounted) return;
      _showSnack(context, enabled ? '关闭前台服务失败' : '开启前台服务失败');
    }
  }

  Future<void> _openVendorSettings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref.read(platformGatewayProvider).openVendorAutostart();
      if (!context.mounted) return;
      _showSnack(context, '请在系统设置中允许自启动，并在最近任务中锁定 MoFox');
    } on Object {
      if (!context.mounted) return;
      _showSnack(context, '无法打开厂商自启动设置');
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.status});

  final KeepaliveStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = status.notificationsGranted &&
        status.ignoringBatteryOptimizations &&
        status.foregroundServiceEnabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  ready
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                  color: ready ? scheme.primary : scheme.error,
                  size: 32,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ready ? '保活关键项已就绪' : '还有保活项需要处理',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        ready ? '通知、前台服务与电池白名单均已启用。' : '按下方状态逐项授权后，后台运行会更稳定。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppStatusBadge(
              label: ready ? '关键项就绪' : '待处理',
              tone: ready ? AppStatusTone.success : AppStatusTone.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepaliveItem extends StatelessWidget {
  const _KeepaliveItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.tone,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final AppStatusTone tone;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Icon(icon, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      AppStatusBadge(label: status, tone: tone),
                      if (actionLabel != null)
                        FilledButton.tonalIcon(
                          onPressed: onPressed,
                          icon: const Icon(Icons.open_in_new),
                          label: Text(actionLabel!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
