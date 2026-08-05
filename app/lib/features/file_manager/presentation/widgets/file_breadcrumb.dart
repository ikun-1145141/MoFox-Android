import 'package:flutter/material.dart';

import '../../domain/rootfs_file_scope.dart';
import '../../domain/rootfs_relative_path.dart';

/// 文件管理页面包屑导航。
///
/// 只能回到当前作用域根，不能继续向上。点击某段跳转到对应路径。
class FileBreadcrumb extends StatelessWidget {
  const FileBreadcrumb({
    required this.scope,
    required this.path,
    required this.onNavigate,
    super.key,
  });

  final RootfsFileScope scope;
  final RootfsRelativePath path;
  final void Function(RootfsRelativePath) onNavigate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final segments = path.segments;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: segments.length + 1,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_right,
          size: 16,
          color: scheme.outline,
        ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return TextButton.icon(
              onPressed: () => onNavigate(const RootfsRelativePath.root()),
              icon: Icon(
                scope.kind == RootfsFileScopeKind.repository
                    ? Icons.folder_outlined
                    : Icons.home_outlined,
                size: 18,
              ),
              label: Text(
                scope.displayName,
                style: text.labelLarge,
              ),
            );
          }
          final target = RootfsRelativePath(segments.take(index));
          final isLast = index == segments.length;
          return TextButton(
            onPressed: isLast ? null : () => onNavigate(target),
            child: Text(
              segments[index - 1],
              style: text.labelLarge?.copyWith(
                fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
                color: isLast ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}
