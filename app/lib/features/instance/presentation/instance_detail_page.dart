import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mofox_android/app/router/app_router.dart';
import 'package:mofox_android/core/ui/ansi_color_text.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/core/ui/explosion_overlay.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_models.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_scope.dart';
import 'package:mofox_android/features/instance/application/instance_deletion_service.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/snowluma_qr_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class InstanceDetailPage extends ConsumerStatefulWidget {
  const InstanceDetailPage({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<InstanceDetailPage> createState() => _InstanceDetailPageState();
}

class _InstanceDetailPageState extends ConsumerState<InstanceDetailPage> {
  /// 用户点了"取消登录"后置位，隐藏扫码浮层直到 snowluma 重新回到运行态。
  bool _loginCancelled = false;

  /// 用户点遮罩手动收起浮层（不停止进程）后置位；进程停止即复位。
  bool _panelDismissed = false;

  Instance get instance => widget.instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final console = ref.watch(processConsoleProvider);
    final installed = instance.installStatus == InstanceInstallStatus.installed;
    final botStatus = console.botStatusFor(instance.id);
    final snowlumaStatus = console.snowlumaStatusFor(instance.id);
    final anotherInstanceActive =
        console.hasRunningProcess && !console.isActiveInstance(instance.id);

    // 扫码浮层不再走 Navigator 模态路由：go_router 的嵌套导航器会随状态刷新
    // 重建，挂在上面的模态路由被悄悄丢弃，造成"弹窗反复弹出"。改为纯 widget
    // 条件渲染——进程在跑且有新截图就显示，停止/取消就隐藏，零 push/pop。
    final snowlumaRunning = snowlumaStatus == 'running';
    final qrPayload = console.snowlumaQrPayload;
    if (!snowlumaRunning) {
      // 进程停了：取消/收起标记一并复位，下次登录恢复默认弹出。
      _loginCancelled = false;
      _panelDismissed = false;
    }
    final showQrPanel = snowlumaRunning &&
        qrPayload != null &&
        !_loginCancelled &&
        !_panelDismissed;
    final showQrRestorePill =
        snowlumaRunning && qrPayload != null && _panelDismissed;

    return Stack(
      children: <Widget>[
        Scaffold(
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
                                    _LiveDot(status: botStatus),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        installed
                                            ? 'Bot ${_processStatusLabel(botStatus)} · SnowLuma ${_processStatusLabel(snowlumaStatus)}'
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
                            onPressed: () => context.push(
                              AppRoute.instanceTerminal,
                              extra: <String, String>{
                                'cwd': instance.repoPath,
                                'title': '${instance.name} - Bot 目录',
                                'instanceId': instance.id,
                              },
                            ),
                            icon: const Icon(Icons.terminal),
                          ),
                          IconButton(
                            tooltip: '文件管理',
                            onPressed: () => context.push(
                              AppRoute.instanceFiles,
                              extra: InstanceFilesRouteArgs(
                                instanceName: instance.name,
                                scope: RootfsFileScope.forInstance(instance),
                              ),
                            ),
                            icon: const Icon(Icons.folder_outlined),
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
                              onPressed: !installed ||
                                      console.isBusy ||
                                      anotherInstanceActive ||
                                      botStatus == 'running'
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
                              onPressed: !installed ||
                                      console.isBusy ||
                                      botStatus != 'running'
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
                              onPressed: !installed ||
                                      console.isBusy ||
                                      botStatus != 'running'
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
                              onPressed: !installed ||
                                      console.isBusy ||
                                      anotherInstanceActive ||
                                      snowlumaStatus == 'running'
                                  ? null
                                  : () {
                                      _loginCancelled = false;
                                      ref
                                          .read(processConsoleProvider.notifier)
                                          .startSnowluma(instance);
                                    },
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('SnowLuma'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !installed ||
                                      console.isBusy ||
                                      snowlumaStatus != 'running'
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .stopSnowluma(),
                              icon: const Icon(Icons.stop),
                              label: const Text('停止'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !installed ||
                                      console.isBusy ||
                                      snowlumaStatus != 'running'
                                  ? null
                                  : () => ref
                                      .read(processConsoleProvider.notifier)
                                      .restartSnowluma(instance),
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
                            child: FilledButton.tonalIcon(
                              onPressed: !installed ||
                                      console.isBusy ||
                                      botStatus != 'running' ||
                                      !instance.installWebui
                                  ? null
                                  : () async => _openWebUi(
                                        context,
                                        target: 'neoMofox',
                                      ),
                              icon: const Icon(Icons.dashboard_outlined),
                              label: const Text('WebUI'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: !installed ||
                                      console.isBusy ||
                                      snowlumaStatus != 'running' ||
                                      !instance.installSnowluma
                                  ? null
                                  : () async => _openWebUi(
                                        context,
                                        target: 'snowluma',
                                      ),
                              icon: const Icon(Icons.qr_code_2_outlined),
                              label: const Text('SnowLuma WebUI'),
                            ),
                          ),
                        ],
                      ),
                      if (anotherInstanceActive) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '另一实例正在运行，请先在对应实例中停止后再切换。',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
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
                  Tab(icon: Icon(Icons.qr_code_2), text: 'SnowLuma'),
                ],
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _ProcessLogPane(lines: console.botLogs),
                    _ProcessLogPane(lines: console.snowlumaLogs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
        ),
        if (showQrPanel)
          _QrLoginOverlay(
            payload: qrPayload,
            onCancel: _cancelLogin,
            onDismiss: () => _setPanelDismissed(true),
            onQuickLogin: () => ref
                .read(processConsoleProvider.notifier)
                .quickLoginQq(),
          ),
        if (showQrRestorePill)
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonalIcon(
                onPressed: () => _setPanelDismissed(false),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('查看扫码窗口'),
              ),
            ),
          ),
      ],
    );
  }

  void _cancelLogin() {
    _loginCancelled = true;
    ref.read(processConsoleProvider.notifier).cancelSnowlumaLogin();
  }

  void _setPanelDismissed(bool value) {
    setState(() => _panelDismissed = value);
  }

  Future<void> _openWebUi(
    BuildContext context, {
    required String target,
  }) async {
    final process = ref.read(processConsoleProvider);
    final url = target == 'snowluma'
        ? process.snowlumaWebuiUrl
        : 'http://127.0.0.1:8000/webui/frontend';

    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SnowLuma WebUI 地址尚未就绪，请稍候再试')),
      );
      return;
    }

    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开系统浏览器')),
        );
      }
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开系统浏览器失败：$error')),
      );
    }
  }

  void _showInstanceInfoSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final scheme = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;
          final botStatus =
              ref.watch(processConsoleProvider).botStatusFor(instance.id);
          return SafeArea(
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
                      _StatusPill(instance: instance, botStatus: botStatus),
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
                        'WebUI 管理面板',
                        instance.installWebui ? '已安装' : '未安装',
                      ),
                      const _DetailRow('SnowLuma', '全局共享'),
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
          );
        },
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

    // 触感反馈不应阻断删除事务。
    try {
      await HapticFeedback.heavyImpact();
    } on Object {
      // Best effort only.
    }
    if (!context.mounted) return;

    // 爆炸粒子动画
    final scheme = Theme.of(context).colorScheme;
    ExplosionOverlay.show(
      context,
      rect: Rect.fromCenter(
        center: Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        ),
        width: 200,
        height: 200,
      ),
      color: scheme.primary,
    );

    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(instanceDeletionServiceProvider.future);
      final process = ref.read(processConsoleProvider);
      await service.delete(
        instance,
        isActive: process.isActiveInstance(instance.id),
        stopActiveProcesses: () => ref
            .read(processConsoleProvider.notifier)
            .stopActiveInstance(instance.id),
      );
      ref.invalidate(instancesProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('实例已删除')));
      context.go(AppRoute.dashboard);
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('删除未完成：$error')));
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
  return switch (status) {
    'running' => '运行中',
    'starting' => '启动中',
    'restarting' => '重启中',
    _ => '已停止',
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.instance, required this.botStatus});

  final Instance instance;
  final String botStatus;

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(
      label: _statusLabel(instance, botStatus),
      tone: _statusTone(instance, botStatus),
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

String _statusLabel(Instance instance, [String botStatus = 'stopped']) {
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

AppStatusTone _statusTone(
  Instance instance, [
  String botStatus = 'stopped',
]) {
  if (instance.installStatus == InstanceInstallStatus.installed &&
      botStatus == 'running') {
    return AppStatusTone.success;
  }
  return switch (instance.installStatus) {
    InstanceInstallStatus.installing => AppStatusTone.warning,
    InstanceInstallStatus.failed => AppStatusTone.error,
    InstanceInstallStatus.installed => AppStatusTone.neutral,
  };
}

/// 页面内的扫码登录浮层。
///
/// 故意不走 Navigator 模态路由：go_router 的嵌套导航器会随状态刷新重建，
/// 挂在上面的模态路由会被悄悄丢弃（表现为"弹窗反复弹出"）。纯 widget
/// 条件渲染没有 push/pop，浮层的显隐完全由进程状态与截图 payload 驱动。
class _QrLoginOverlay extends StatelessWidget {
  const _QrLoginOverlay({
    required this.payload,
    required this.onCancel,
    required this.onDismiss,
    required this.onQuickLogin,
  });

  final String payload;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final VoidCallback onQuickLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.black54),
          ),
        ),
        Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SnowlumaQrSheet(
                payload: payload,
                onCancel: onCancel,
                onClose: onDismiss,
                onQuickLogin: onQuickLogin,
              ),
            ),
          ),
        ),
        ),
      ],
    );
  }
}
