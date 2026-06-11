import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../application/app_settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final terminalHapticsEnabled =
        settings.valueOrNull?.terminalHapticsEnabled ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const _Section(
            title: '外观',
            children: <Widget>[
              _SettingTile(
                leading: Icon(Icons.palette_outlined),
                title: '主题模式',
                subtitle: '跟随系统',
                trailing: Icon(Icons.chevron_right),
              ),
              _Divider(),
              _SettingTile(
                leading: Icon(Icons.format_color_fill_outlined),
                title: '动态取色',
                subtitle: '使用系统壁纸生成 Material You 颜色',
                trailing: Switch(value: true, onChanged: null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '终端',
            children: <Widget>[
              _SettingTile(
                leading: const Icon(Icons.vibration_outlined),
                title: '触感反馈',
                subtitle: '长按选择、复制和快捷键按钮震动',
                trailing: Switch(
                  value: terminalHapticsEnabled,
                  onChanged: settings.isLoading
                      ? null
                      : (value) => ref
                          .read(appSettingsProvider.notifier)
                          .setTerminalHapticsEnabled(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            title: '运行时',
            children: <Widget>[
              _SettingTile(
                leading: Icon(Icons.smart_toy_outlined),
                title: 'Bot 进程',
                subtitle: '已停止',
                trailing: _StatusDot(active: false),
              ),
              _Divider(),
              _SettingTile(
                leading: Icon(Icons.qr_code_2_outlined),
                title: 'Napcat',
                subtitle: '已停止',
                trailing: _StatusDot(active: false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            title: '保活体检',
            children: <Widget>[
              _SettingTile(
                leading: Icon(Icons.shield_outlined),
                title: '查看保活状态',
                subtitle: '前台服务 / 电池白名单 / 自启动',
                trailing: Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            title: '备份与导出',
            children: <Widget>[
              _SettingTile(
                leading: Icon(Icons.archive_outlined),
                title: '一键打包导出',
                subtitle: 'toml + Napcat 登录态 + 最近 N 天日志',
                trailing: Icon(Icons.chevron_right),
              ),
              _Divider(),
              _SettingTile(
                leading: Icon(Icons.tune_outlined),
                title: '选择性导出',
                subtitle: '单独导出 core.toml / model.toml / napcat / 日志',
                trailing: Icon(Icons.chevron_right),
              ),
              _Divider(),
              _SettingTile(
                leading: Icon(Icons.unarchive_outlined),
                title: '从备份导入',
                trailing: Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '关于',
            children: <Widget>[
              _SettingTile(
                leading: const Icon(Icons.info_outline),
                title: '关于 MoFox',
                subtitle: '版本、开源许可与源代码',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoute.about),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 72),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? scheme.primary : scheme.outline,
      ),
    );
  }
}
