import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mofox_android/core/platform/platform_gateway.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';

/// 手机信息桥接设置页。
///
/// 管理短信桥接的开关与权限：开启后，手机收到的短信会写入 rootfs 的
/// 桥接文件，由 Bot 侧 mofox_sms_bridge 插件识别快递/取件码等有用信息，
/// 主动私信主人开启话题。本页还提供「发送测试」按钮注入一条模拟快递
/// 短信，用于验证端到端链路。
class SmsBridgePage extends ConsumerStatefulWidget {
  const SmsBridgePage({super.key});

  @override
  ConsumerState<SmsBridgePage> createState() => _SmsBridgePageState();
}

class _SmsBridgePageState extends ConsumerState<SmsBridgePage> {
  SmsBridgeStatus? _status;
  bool _loading = true;
  bool _working = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status =
          await ref.read(platformGatewayProvider).getSmsBridgeStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _errorMessage = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '无法读取短信桥接状态，请重试。';
      });
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _working = true);
    try {
      final gateway = ref.read(platformGatewayProvider);
      if (value) {
        final granted = await _ensureSmsPermission();
        if (!granted) {
          _showSnackBar('需要「短信」权限才能接收短信事件，请在系统设置中授权');
          await _refresh();
          return;
        }
      }
      await gateway.setSmsBridgeEnabled(enabled: value);
    } on Object {
      _showSnackBar('保存短信桥接开关失败');
    } finally {
      if (mounted) setState(() => _working = false);
      await _refresh();
    }
  }

  Future<bool> _ensureSmsPermission() async {
    var current = await Permission.sms.status;
    if (current.isGranted) return true;
    if (current.isPermanentlyDenied) {
      _showSnackBar('短信权限已被拒绝，请到系统设置中手动开启');
      await openAppSettings();
      return false;
    }
    current = await Permission.sms.request();
    return current.isGranted;
  }

  Future<void> _sendTest() async {
    setState(() => _working = true);
    try {
      final ok = await ref.read(platformGatewayProvider).sendSmsBridgeTest();
      if (!mounted) return;
      _showSnackBar(
        ok
            ? '测试短信已写入桥接文件，Bot 运行中时稍候几秒会主动私聊你'
            : '写入失败：请先开启开关并确认运行时已安装',
      );
    } on Object {
      _showSnackBar('发送测试事件失败');
    } finally {
      if (mounted) setState(() => _working = false);
      await _refresh();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('手机信息桥接')),
      body: _loading
          ? const AppLoadingState(label: '正在读取桥接状态')
          : AppPageList(
              children: <Widget>[
                AppSectionCard(
                  title: '短信桥接',
                  children: <Widget>[
                    AppSwitchSettingTile(
                      secondary: const Icon(Icons.sms_outlined),
                      title: '转发手机短信给 Bot',
                      subtitle: '收到的短信写入桥接文件，由 Bot 识别后主动提醒你',
                      value: status?.enabled ?? false,
                      onChanged: _working ? null : _toggleEnabled,
                    ),
                    AppSettingTile(
                      leading: Icon(
                        _statusIcon(status),
                        color: _statusIconColor(context, status),
                      ),
                      title: '授权与运行时状态',
                      subtitle: _statusText(status),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _refresh,
                    ),
                    AppSettingTile(
                      leading: const Icon(Icons.science_outlined),
                      title: '发送测试短信',
                      subtitle: '模拟一条含取件码的快递短信，验证 Bot 能否主动开话题',
                      trailing: _working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _working ? null : _sendTest,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  title: '工作方式',
                  children: <Widget>[
                    const AppSettingTile(
                      leading: Icon(Icons.info_outline),
                      title: '识别范围',
                      subtitle: '默认转发快递/取件码、账单、行程提醒；'
                          '验证码默认不转发，广告短信自动过滤。'
                          '可在 Bot 插件配置 config/plugins/mofox_sms_bridge/config.toml 中调整',
                    ),
                    const AppSettingTile(
                      leading: Icon(Icons.schedule_outlined),
                      title: '提醒对象',
                      subtitle: '默认私聊 Bot 主人（core.toml 的 owner_list），'
                          '也可在插件配置 notify.target_list 里指定其他 QQ',
                    ),
                  ],
                ),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  AppErrorState(
                    title: '状态读取失败',
                    message: _errorMessage ?? '',
                    onRetry: _refresh,
                  ),
                ],
              ],
            ),
    );
  }

  IconData _statusIcon(SmsBridgeStatus? status) {
    if (status == null) return Icons.help_outline;
    if (!status.rootfsReady) return Icons.storage_outlined;
    if (!status.smsPermissionGranted) return Icons.lock_outline;
    if (status.enabled) return Icons.check_circle_outline;
    return Icons.toggle_off_outlined;
  }

  Color? _statusIconColor(BuildContext context, SmsBridgeStatus? status) {
    if (status == null) return null;
    if (status.usable && status.enabled) return Theme.of(context).colorScheme.primary;
    return Theme.of(context).colorScheme.error;
  }

  String _statusText(SmsBridgeStatus? status) {
    if (status == null) return '点击重试';
    final parts = <String>[
      status.smsPermissionGranted ? '短信权限已授予' : '缺少短信权限',
      status.rootfsReady ? '运行时就绪' : '运行时未安装',
    ];
    if (status.enabled && status.bridgeFileExists) {
      parts.add('桥接文件 ${_formatBytes(status.bridgeFileSize)}');
    }
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
