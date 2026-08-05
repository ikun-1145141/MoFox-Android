import 'package:flutter/material.dart';

import '../../domain/rootfs_file_models.dart';

/// 目录列表中的单个文件/目录条目。
class RootfsFileTile extends StatelessWidget {
  const RootfsFileTile({
    required this.entry,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final RootfsFileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final icon = _iconFor(entry);
    final iconColor = entry.isDirectory
        ? scheme.primary
        : entry.isToml
            ? scheme.tertiary
            : scheme.onSurfaceVariant;
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        entry.name,
        style: text.bodyLarge?.copyWith(
          fontFamily: entry.isToml ? 'monospace' : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.sizeBytes == null
          ? null
          : Text(
              _formatSize(entry.sizeBytes!) +
                  ' · ' +
                  _formatDate(entry.modifiedAt),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
      trailing: PopupMenuButton<_FileAction>(
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case _FileAction.rename:
              onRename();
            case _FileAction.delete:
              onDelete();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _FileAction.rename,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('重命名'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: _FileAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('删除', style: TextStyle(color: scheme.error)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  IconData _iconFor(RootfsFileEntry entry) {
    switch (entry.kind) {
      case RootfsFileKind.directory:
        return Icons.folder;
      case RootfsFileKind.file:
        return entry.isToml
            ? Icons.description
            : Icons.insert_drive_file_outlined;
      case RootfsFileKind.symlink:
        return Icons.shortcut;
      case RootfsFileKind.other:
        return Icons.help_outline;
    }
  }
}

enum _FileAction { rename, delete }

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
