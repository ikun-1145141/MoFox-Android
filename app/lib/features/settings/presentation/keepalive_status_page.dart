import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/platform/platform_gateway.dart';

final keepaliveStatusProvider = FutureProvider.autoDispose<KeepaliveStatus>(
  (ref) => ref.watch(platformGatewayProvider).getKeepaliveStatus(),
);

class KeepaliveStatusPage extends ConsumerWidget {
  const KeepaliveStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(keepaliveStatusProvider);
    final platform = ref.watch(platformGatewayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('保活状态'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(keepaliveStatusProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(keepaliveStatusProvider.future),
        child: status.when(
          data: (value) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _StatusCard(status: value),
              const SizedBox(height: 16),
              _StatusTile(
                icon: Icons.notifications_active_outlined,
                title: '通知权限',
                description: '前台保活服务需要显示常驻通知。',
                granted: value.notificationsGranted,
                actionLabel: value.notificationsGranted ? '已授权' : '去授权',
                onPressed: value.notificationsGranted
                    ? null
                    : () => _requestNotification(context, ref, platform),
              ),
              const SizedBox(height: 12),
              _StatusTile(
                icon: Icons.battery_charging_full_outlined,
                title: '忽略电池优化',
                description: '允许 MoFox 在后台更稳定地运行 Bot。',
                granted: value.ignoringBatteryOptimizations,
                actionLabel: value.ignoringBatteryOptimizations ? '已加入' : '去设置',
                onPressed: value.ignoringBatteryOptimizations
                    ? null
                    : () => _requestBatteryOptimization(context, ref, platform),
              ),
              const SizedBox(height: 12),
              _StatusTile(
                icon: Icons.sync_lock_outlined,
                title: '前台保活服务',
                description: '开启后 MoFox 会保留一个守护通知。',
                granted: value.foregroundServiceEnabled,
                actionLabel: value.foregroundServiceEnabled ? '关闭' : '开启',
                onPressed: () => _toggleForegroundService(
                  context,
                  ref,
                  platform,
                  enabled: value.foregroundServiceEnabled,
                ),
              ),
              const SizedBox(height: 12),
              _StatusTile(
                icon: Icons.restart_alt_outlined,
                title: '开机自启声明',
                description: '应用已声明开机广播接收器，实际触发受系统策略限制。',
                granted: value.bootReceiverDeclared,
                actionLabel: '已声明',
                onPressed: null,
              ),
              const SizedBox(height: 12),
              _StatusTile(
                icon: Icons.lock_outline,
                title: '厂商自启动 / 最近任务锁定',
                description: 'Android 没有统一查询接口，需要在系统页确认。',
                granted: value.vendorAutostartInspectable,
                actionLabel: '打开设置',
                onPressed: () => _openVendorSettings(context, platform),
              ),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _ErrorPanel(
                message: '读取保活状态失败：$error',
                onRetry: () => ref.invalidate(keepaliveStatusProvider),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _requestNotification(
    BuildContext context,
    WidgetRef ref,
    PlatformGateway platform,
  ) async {
    final permission = await Permission.notification.request();
    if (!context.mounted) return;
    if (permission.isGranted) {
      await platform.startForegroundService();
      ref.invalidate(keepaliveStatusProvider);
      if (!context.mounted) return;
      _showSnack(context, '通知权限已开启，前台保活服务已启动');
      return;
    }
    if (permission.isPermanentlyDenied) {
      await openAppSettings();
    }
    ref.invalidate(keepaliveStatusProvider);
    if (!context.mounted) return;
    _showSnack(context, '请允许通知权限，否则前台保活服务无法稳定运行');
  }

  Future<void> _requestBatteryOptimization(
    BuildContext context,
    WidgetRef ref,
    PlatformGateway platform,
  ) async {
    final granted = await platform.requestIgnoreBatteryOptimizations();
    ref.invalidate(keepaliveStatusProvider);
    if (!context.mounted) return;
    _showSnack(context, granted ? '已在电池优化白名单中' : '已打开电池优化授权页');
  }

  Future<void> _toggleForegroundService(
    BuildContext context,
    WidgetRef ref,
    PlatformGateway platform, {
    required bool enabled,
  }) async {
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
  }

  Future<void> _openVendorSettings(
    BuildContext context,
    PlatformGateway platform,
  ) async {
    await platform.openVendorAutostart();
    if (!context.mounted) return;
    _showSnack(context, '请在系统设置中允许自启动，并在最近任务中锁定 MoFox');
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final KeepaliveStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = status.notificationsGranted &&
        status.ignoringBatteryOptimizations &&
        status.foregroundServiceEnabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor:
                  ready ? scheme.primaryContainer : scheme.errorContainer,
              child: Icon(
                ready ? Icons.verified_outlined : Icons.warning_amber_outlined,
                color:
                    ready ? scheme.onPrimaryContainer : scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ready ? '保活关键项已就绪' : '还有保活项需要处理',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
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
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: FilledButton.tonalIcon(
          onPressed: onPressed,
          icon:
              Icon(granted ? Icons.check_circle_outline : Icons.chevron_right),
          label: Text(actionLabel),
        ),
        iconColor: granted ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
