import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';
import '../application/backup_service.dart';

/// 备份与导出页面。
///
/// 三个功能入口：
/// 1. 一键打包导出 — config + napcat 登录态 + 日志 → ZIP → SAF
/// 2. 选择性导出 — 单独导出 core.toml / model.toml / napcat / 日志
/// 3. 从备份导入 — SAF 读取 ZIP → 恢复到实例目录
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  Instance? _selectedInstance;
  bool _includeLogs = true;

  @override
  Widget build(BuildContext context) {
    final instances = ref.watch(instancesProvider);
    final backupState = ref.watch(backupNotifierProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('备份与导出')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          // 实例选择器
          _Section(
            title: '选择实例',
            children: <Widget>[
              instances.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const _InfoTile(text: '暂无实例，请先创建');
                  }
                  return DropdownButtonFormField<Instance>(
                    value: _selectedInstance ?? list.first,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    items: list
                        .map((inst) => DropdownMenuItem(
                              value: inst,
                              child: Text('${inst.name} (${inst.botQq})'),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedInstance = value),
                  );
                },
                loading: () => const _InfoTile(text: '加载中…'),
                error: (e, _) => _InfoTile(text: '加载失败: $e'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 一键打包导出
          _Section(
            title: '一键打包导出',
            children: <Widget>[
              _SettingTile(
                leading: const Icon(Icons.archive_outlined),
                title: '打包导出',
                subtitle: 'config + Napcat 登录态 + 最近日志',
                trailing: backupState.isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap:
                    backupState.isExporting ? null : () => _exportFullBackup(),
              ),
              const _Divider(),
              SwitchListTile(
                title: const Text('包含日志'),
                subtitle: const Text('导出最近 7 天的运行日志'),
                value: _includeLogs,
                onChanged: (value) => setState(() => _includeLogs = value),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 选择性导出
          _Section(
            title: '选择性导出',
            children: <Widget>[
              _SettingTile(
                leading: const Icon(Icons.description_outlined),
                title: 'core.toml',
                subtitle: 'Bot 核心配置',
                trailing: const Icon(Icons.download_outlined),
                onTap: backupState.isExporting
                    ? null
                    : () => _exportSingle('core.toml', 'config/core.toml'),
              ),
              const _Divider(),
              _SettingTile(
                leading: const Icon(Icons.memory_outlined),
                title: 'model.toml',
                subtitle: '模型 API 配置',
                trailing: const Icon(Icons.download_outlined),
                onTap: backupState.isExporting
                    ? null
                    : () => _exportSingle('model.toml', 'config/model.toml'),
              ),
              const _Divider(),
              _SettingTile(
                leading: const Icon(Icons.hub_outlined),
                title: 'adapter.toml',
                subtitle: 'NapCat 适配器配置',
                trailing: const Icon(Icons.download_outlined),
                onTap: backupState.isExporting
                    ? null
                    : () =>
                        _exportSingle('adapter.toml', 'config/adapter.toml'),
              ),
              const _Divider(),
              _SettingTile(
                leading: const Icon(Icons.qr_code_2_outlined),
                title: 'NapCat 配置',
                subtitle: 'NapCat WebSocket 等配置',
                trailing: const Icon(Icons.download_outlined),
                onTap: backupState.isExporting
                    ? null
                    : () => _exportSingle(
                          'napcat-config',
                          '/root/napcat/config',
                        ),
              ),
              const _Divider(),
              _SettingTile(
                leading: const Icon(Icons.article_outlined),
                title: '运行日志',
                subtitle: '最近 7 天日志',
                trailing: const Icon(Icons.download_outlined),
                onTap: backupState.isExporting
                    ? null
                    : () => _exportSingle('logs', 'logs'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 从备份导入
          _Section(
            title: '从备份导入',
            children: <Widget>[
              _SettingTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: '导入备份',
                subtitle: '从 ZIP 文件恢复配置',
                trailing: backupState.isImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: backupState.isImporting ? null : () => _importBackup(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 状态消息
          if (backupState.message != null || backupState.error != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (backupState.error != null
                        ? scheme.errorContainer
                        : scheme.surfaceContainerHighest)
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    backupState.error != null
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: backupState.error != null
                        ? scheme.error
                        : scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      backupState.error ?? backupState.message!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _exportFullBackup() async {
    final instance = _selectedInstance;
    if (instance == null) {
      _showSnackBar('请先选择实例');
      return;
    }
    final uri =
        await ref.read(backupNotifierProvider.notifier).exportFullBackup(
              instance: instance,
              includeLogs: _includeLogs,
            );
    if (uri != null) {
      _showSnackBar('导出成功');
    }
  }

  Future<void> _exportSingle(String name, String relativePath) async {
    final instance = _selectedInstance;
    if (instance == null) {
      _showSnackBar('请先选择实例');
      return;
    }
    final rootfsPath = relativePath.startsWith('/')
        ? relativePath
        : '${instance.repoPath}/$relativePath';
    final uri = await ref.read(backupNotifierProvider.notifier).exportSingle(
          instance: instance,
          rootfsPath: rootfsPath,
          exportName: name,
        );
    if (uri != null) {
      _showSnackBar('导出成功');
    }
  }

  Future<void> _importBackup() async {
    final instance = _selectedInstance;
    if (instance == null) {
      _showSnackBar('请先选择实例');
      return;
    }
    final count = await ref
        .read(backupNotifierProvider.notifier)
        .importBackup(instance: instance);
    if (count > 0) {
      _showSnackBar('导入成功（$count 个文件）');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
