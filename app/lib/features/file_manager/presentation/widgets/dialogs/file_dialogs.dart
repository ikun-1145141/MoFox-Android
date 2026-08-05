import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 文件操作对话框集合：新建目录、新建 TOML 文件、重命名、删除确认。

/// 新建目录对话框。返回用户输入的名称，取消返回 null。
Future<String?> showCreateDirectoryDialog(BuildContext context) {
  return _showNameDialog(
    context: context,
    title: '新建目录',
    label: '目录名',
    hint: '输入目录名',
  );
}

/// 新建 TOML 文件对话框。返回用户输入的文件名（自动补 .toml 后缀）。
Future<String?> showCreateTomlFileDialog(BuildContext context) async {
  final name = await _showNameDialog(
    context: context,
    title: '新建 TOML 文件',
    label: '文件名',
    hint: '例如 config（自动添加 .toml 后缀）',
  );
  if (name == null) return null;
  if (!name.toLowerCase().endsWith('.toml')) return '$name.toml';
  return name;
}

/// 重命名对话框。预填当前名称。
Future<String?> showRenameDialog(
  BuildContext context,
  String currentName,
) {
  return _showNameDialog(
    context: context,
    title: '重命名',
    label: '新名称',
    hint: '输入新名称',
    initial: currentName,
  );
}

/// 删除确认对话框。recursive 用于递归删除目录。
/// 返回 true 表示确认删除。
Future<bool> showDeleteConfirmDialog(
  BuildContext context,
  String name, {
  required bool isDirectory,
  required bool recursive,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber, color: scheme.error),
      title: const Text('删除？'),
      content: Text(isDirectory && recursive
          ? '将递归删除目录「$name」及其所有内容。此操作无法撤销。'
          : '将删除「$name」。此操作无法撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  ).then((v) => v ?? false);
}

Future<String?> _showNameDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String hint,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          inputFormatters: [
            LengthLimitingTextInputFormatter(255),
            // 禁止路径分隔符和特殊字符
            FilteringTextInputFormatter.deny(RegExp(r'[/\\\u0000]')),
          ],
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return '名称不能为空';
            if (v == '.' || v == '..') return '不能使用此名称';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              Navigator.of(ctx).pop(controller.text.trim());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
