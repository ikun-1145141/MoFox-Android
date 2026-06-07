import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: const <Widget>[
          _SectionHeader('外观'),
          ListTile(
            leading: Icon(Icons.color_lens_outlined),
            title: Text('主题模式'),
            subtitle: Text('跟随系统'),
          ),
          _SectionHeader('运行时'),
          ListTile(
            leading: Icon(Icons.play_circle_outline),
            title: Text('Bot 进程'),
            subtitle: Text('已停止'),
          ),
          ListTile(
            leading: Icon(Icons.qr_code_2_outlined),
            title: Text('Napcat'),
            subtitle: Text('已停止'),
          ),
          _SectionHeader('保活体检'),
          ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('查看保活状态'),
          ),
          _SectionHeader('备份与导出'),
          ListTile(
            leading: Icon(Icons.archive_outlined),
            title: Text('一键打包导出'),
            subtitle: Text('toml + Napcat 登录态 + 最近 N 天日志'),
          ),
          ListTile(
            leading: Icon(Icons.tune_outlined),
            title: Text('选择性导出'),
            subtitle: Text('单独导出 core.toml / model.toml / napcat config / 日志'),
          ),
          ListTile(
            leading: Icon(Icons.unarchive_outlined),
            title: Text('从备份导入'),
          ),
          _SectionHeader('关于'),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本与开源许可'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        title,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
