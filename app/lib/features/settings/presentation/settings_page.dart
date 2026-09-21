import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mofox_android/app/router/app_router.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/assistant/application/assistant_settings_notifier.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/settings/application/app_settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final assistant = ref.watch(assistantSettingsProvider);
    final process = ref.watch(processConsoleProvider);
    final instances = ref.watch(instancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settings.when(
        loading: () => const AppLoadingState(label: '正在加载设置'),
        error: (_, __) => AppErrorState(
          title: '设置加载失败',
          message: '暂时无法读取本机设置，请重试。',
          onRetry: () => ref.invalidate(appSettingsProvider),
        ),
        data: (appSettings) {
          final activeInstanceLabel = _activeInstanceLabel(
            instances.valueOrNull,
            process.activeInstanceId,
          );
          final botStatus =
              process.activeInstanceId == null ? 'stopped' : process.botStatus;
          final napcatStatus = process.activeInstanceId == null
              ? 'stopped'
              : process.napcatStatus;
          final appearanceSubtitle = '${appSettings.themeMode.label} · '
              '${appSettings.dynamicColorEnabled ? '动态取色' : '品牌色'} · '
              '${appSettings.mainImageMode.label}';
          final assistantPresentation = assistant.when(
            loading: () => const _AssistantPresentation(
              icon: Icons.hourglass_top_outlined,
              subtitle: '正在读取配置…',
            ),
            error: (_, __) => const _AssistantPresentation(
              icon: Icons.error_outline,
              subtitle: '配置读取失败，点按查看',
            ),
            data: (value) => _AssistantPresentation(
              icon:
                  value.yoloEnabled ? Icons.bolt : Icons.auto_awesome_outlined,
              subtitle: value.configured
                  ? '${value.model} · ${value.yoloEnabled ? 'YOLO' : '副驾驶'}'
                  : !value.enabled &&
                          value.baseUrl.isNotEmpty &&
                          value.model.isNotEmpty &&
                          value.hasApiKey
                      ? '已配置 · 未启用'
                      : '配置不完整',
            ),
          );

          return AppPageList(
            children: <Widget>[
              AppSectionCard(
                title: '外观',
                children: <Widget>[
                  AppSettingTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: '外观与主题',
                    subtitle: appearanceSubtitle,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.appearance),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '终端',
                children: <Widget>[
                  AppSwitchSettingTile(
                    secondary: const Icon(Icons.vibration_outlined),
                    title: '触感反馈',
                    subtitle: '长按选择、复制和快捷键按钮震动',
                    value: appSettings.terminalHapticsEnabled,
                    onChanged: (value) async {
                      try {
                        await ref
                            .read(appSettingsProvider.notifier)
                            .setTerminalHapticsEnabled(value);
                      } on Object {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('保存触感反馈设置失败')),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'AI 运维助手',
                children: <Widget>[
                  AppSettingTile(
                    leading: Icon(assistantPresentation.icon),
                    title: '模型与操作模式',
                    subtitle: assistantPresentation.subtitle,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.assistantSettings),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '运行时',
                children: <Widget>[
                  AppSettingTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: 'Bot 进程',
                    subtitle: process.errorMessage == null
                        ? _processStatusLabel(
                            botStatus,
                            activeInstanceLabel: activeInstanceLabel,
                          )
                        : '状态刷新失败，显示的状态可能已过期',
                    trailing: _processStatusBadge(
                      botStatus,
                      stale: process.errorMessage != null,
                    ),
                  ),
                  AppSettingTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: 'NapCat',
                    subtitle: process.errorMessage == null
                        ? _processStatusLabel(
                            napcatStatus,
                            activeInstanceLabel: activeInstanceLabel,
                          )
                        : '状态刷新失败，显示的状态可能已过期',
                    trailing: _processStatusBadge(
                      napcatStatus,
                      stale: process.errorMessage != null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '保活体检',
                children: <Widget>[
                  AppSettingTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: '查看保活状态',
                    subtitle: '前台服务 / 电池白名单 / 自启动',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.keepaliveStatus),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '备份与导出',
                children: <Widget>[
                  AppSettingTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: '一键打包导出',
                    subtitle: 'TOML 配置 + NapCat 登录态 + 最近 7 天日志',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.backup),
                  ),
                  AppSettingTile(
                    leading: const Icon(Icons.tune_outlined),
                    title: '选择性导出',
                    subtitle: '单独导出 core.toml、model.toml、NapCat 或日志',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.backup),
                  ),
                  AppSettingTile(
                    leading: const Icon(Icons.unarchive_outlined),
                    title: '从备份导入',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.backup),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '关于',
                children: <Widget>[
                  AppSettingTile(
                    leading: const Icon(Icons.info_outline),
                    title: '关于 MoFox',
                    subtitle: '版本、开源许可与源代码',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoute.about),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AssistantPresentation {
  const _AssistantPresentation({required this.icon, required this.subtitle});

  final IconData icon;
  final String subtitle;
}

String _processStatusLabel(
  String status, {
  String? activeInstanceLabel,
}) =>
    switch (status) {
      'running' =>
        activeInstanceLabel == null ? '正在运行' : '正在运行 · $activeInstanceLabel',
      'stopped' => '已停止',
      _ => '状态未知',
    };

String? _activeInstanceLabel(
  List<Instance>? instances,
  String? activeInstanceId,
) {
  if (activeInstanceId == null) return null;
  for (final instance in instances ?? const <Instance>[]) {
    if (instance.id == activeInstanceId) return instance.name;
  }
  return '实例 $activeInstanceId';
}

Widget _processStatusBadge(String status, {required bool stale}) {
  if (stale) {
    return const AppStatusBadge(
      label: '待刷新',
      tone: AppStatusTone.warning,
    );
  }
  return switch (status) {
    'running' => const AppStatusBadge(
        label: '运行中',
        tone: AppStatusTone.success,
      ),
    'stopped' => const AppStatusBadge(
        label: '已停止',
        tone: AppStatusTone.neutral,
      ),
    _ => const AppStatusBadge(
        label: '未知',
        tone: AppStatusTone.warning,
      ),
  };
}
