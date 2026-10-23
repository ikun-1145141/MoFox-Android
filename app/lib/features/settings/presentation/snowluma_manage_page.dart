import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/settings/application/snowluma_maintenance_provider.dart';

/// 「设置 → SnowLuma 管理目录」。
///
/// SnowLuma 运行时全局唯一、所有实例共享，因此这里提供的是运行时级的
/// 维护入口：幂等检查修复 + 重启应用更新。启动/重启的日常操作仍在
/// dashboard；本页不承担每次启动的安装职责（首次安装走 OOBE，升级走
/// 启动脚本内的版本对齐）。
class SnowlumaManagePage extends ConsumerStatefulWidget {
  const SnowlumaManagePage({super.key});

  @override
  ConsumerState<SnowlumaManagePage> createState() =>
      _SnowlumaManagePageState();
}

class _SnowlumaManagePageState extends ConsumerState<SnowlumaManagePage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(snowlumaMaintenanceProvider.notifier).refreshInstalledVersion(),
    );
  }

  Future<void> _confirmRepair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检查并修复 SnowLuma？'),
        content: const Text(
          '将对 SnowLuma 运行时做幂等检查与修复。\n\n'
          '· 若本次安装了新版本，需要重启 SnowLuma 后才能生效；\n'
          '· SnowLuma 正在运行时执行是安全的（当前进程继续使用旧版本）。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success =
        await ref.read(snowlumaMaintenanceProvider.notifier).checkAndRepair();
    if (!mounted) return;
    final message = ref.read(snowlumaMaintenanceProvider).lastResultMessage;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(success ? '维护完成' : '维护失败'),
        content: Text(message ?? ''),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRestart() async {
    final instances = await ref.read(instancesProvider.future);
    if (!mounted) return;
    if (instances.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到实例，请先创建实例')),
      );
      return;
    }
    final console = ref.read(processConsoleProvider.notifier);
    final activeInstanceId = ref.read(processConsoleProvider).activeInstanceId;
    var selected = instances.firstWhere(
      (instance) => instance.id == activeInstanceId,
      orElse: () => instances.first,
    );
    if (instances.length > 1) {
      final picked = await showDialog<Instance>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择实例'),
          children: <Widget>[
            for (final instance in instances)
              RadioListTile<String>(
                value: instance.id,
                groupValue: selected.id,
                onChanged: (value) =>
                    Navigator.of(context).pop(instance),
                title: Text(instance.name),
                subtitle: Text('QQ ${instance.botQq}'),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      selected = picked;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重启 SnowLuma？'),
        content: Text(
          '实例：${selected.name}（QQ ${selected.botQq}）\n\n'
          'SnowLuma 运行时全局唯一，重启影响所有共享它的实例；'
          '用于应用更新或恢复运行。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重启'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await console.restartSnowluma(selected);
    if (!mounted) return;
    final error = ref.read(processConsoleProvider).errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? '重启指令已发出，更新将在重启后生效',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maintenance = ref.watch(snowlumaMaintenanceProvider);
    final console = ref.watch(processConsoleProvider);
    final busy = maintenance.running || console.isBusy;

    return Scaffold(
      appBar: AppBar(title: const Text('SnowLuma 管理目录')),
      body: AppPageList(
        children: <Widget>[
          AppSectionCard(
            title: '运行状态',
            addDividers: false,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('已安装版本'),
                subtitle: Text(maintenance.installedVersion ?? '检测中…'),
              ),
              ListTile(
                leading: Icon(
                  console.snowlumaStatus == 'running'
                      ? Icons.play_circle_outline
                      : Icons.stop_circle_outlined,
                ),
                title: const Text('进程状态'),
                subtitle: Text(
                  console.snowlumaStatus == 'running' ? '运行中' : '已停止',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  'SnowLuma 运行时全局唯一，所有实例共享；'
                  '日常启停请使用实例页，本页用于运行时维护。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionCard(
            title: '维护操作',
            children: <Widget>[
              AppSettingTile(
                leading: const Icon(Icons.build_outlined),
                title: '检查并修复运行时',
                subtitle: '幂等检查；若安装了新版本需重启后生效',
                enabled: !busy,
                trailing: maintenance.running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: busy ? null : () => unawaited(_confirmRepair()),
              ),
              AppSettingTile(
                leading: const Icon(Icons.restart_alt),
                title: '重启 SnowLuma',
                subtitle: '应用更新或恢复运行；影响所有共享实例',
                enabled: !busy,
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => unawaited(_confirmRestart()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionCard(
            title: '执行日志',
            addDividers: false,
            contentPadding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              _LogPane(logs: maintenance.logs),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogPane extends StatelessWidget {
  const _LogPane({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Text(
        '暂无日志。执行维护操作后，任务输出会显示在这里。',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final visible = logs.length > 200 ? logs.sublist(logs.length - 200) : logs;
    return SizedBox(
      height: 240,
      child: SingleChildScrollView(
        reverse: true,
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final line in visible)
                Text(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
