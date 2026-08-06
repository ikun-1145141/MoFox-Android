import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../application/file_browser_notifier.dart';
import '../application/file_browser_state.dart';
import '../application/rootfs_file_repository.dart';
import '../domain/rootfs_file_exception.dart';
import '../domain/rootfs_file_models.dart';
import '../domain/rootfs_file_scope.dart';
import '../domain/text_file_language.dart';
import 'widgets/dialogs/file_dialogs.dart';
import 'widgets/file_breadcrumb.dart';
import 'widgets/rootfs_file_tile.dart';

/// 实例文件管理页。
///
/// 浏览容器内当前实例相关目录，支持分页、刷新、新建、重命名、删除。
/// 点击 TOML 文件进入编辑器。
class InstanceFilesPage extends ConsumerWidget {
  const InstanceFilesPage({required this.args, super.key});

  final InstanceFilesRouteArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = args.scope;
    final key = FileBrowserKey(
      scope: scope,
      initialPath: args.initialRelativePath,
    );
    final state = ref.watch(fileBrowserProvider(key));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text('${args.instanceName} · 文件'),
        actions: [
          // 作用域切换
          PopupMenuButton<RootfsFileScopeKind>(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换作用域',
            onSelected: (kind) =>
                ref.read(fileBrowserProvider(key).notifier).switchScope(kind),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: RootfsFileScopeKind.repository,
                child: ListTile(
                  leading: Icon(Icons.folder_outlined),
                  title: Text('Bot 仓库'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: RootfsFileScopeKind.instance,
                child: ListTile(
                  leading: Icon(Icons.home_outlined),
                  title: Text('实例目录'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: state.isLoading
                ? null
                : () => ref.read(fileBrowserProvider(key).notifier).refresh(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: '新建',
            onSelected: (action) async {
              switch (action) {
                case 'directory':
                  await _createDirectory(context, ref, key, state);
                case 'toml':
                  await _createTomlFile(context, ref, key, state);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'directory',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('新建目录'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'toml',
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('新建 TOML 文件'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(context, ref, key, state),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    FileBrowserKey key,
    FileBrowserState state,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null && state.entries.isEmpty) {
      return _ErrorView(
        message: state.errorMessage!,
        onRetry: () => ref.read(fileBrowserProvider(key).notifier).refresh(),
      );
    }
    if (state.entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(fileBrowserProvider(key).notifier).refresh(),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text('目录为空', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        FileBreadcrumb(
          scope: state.scope,
          path: state.path,
          onNavigate: (path) =>
              ref.read(fileBrowserProvider(key).notifier).openDirectory(path),
        ),
        if (state.errorMessage != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(fileBrowserProvider(key).notifier).refresh(),
            child: ListView.builder(
              itemCount: state.entries.length +
                  (state.hasMore ? 1 : 0) +
                  (state.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < state.entries.length) {
                  final entry = state.entries[index];
                  return RootfsFileTile(
                    entry: entry,
                    onTap: () => _onEntryTap(context, ref, key, state, entry),
                    onRename: () => _rename(context, ref, key, entry),
                    onDelete: () => _delete(context, ref, key, entry),
                  );
                }
                // 加载更多指示器
                if (!state.isLoadingMore && state.hasMore) {
                  // 触发加载
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(fileBrowserProvider(key).notifier).loadMore();
                  });
                }
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _onEntryTap(
    BuildContext context,
    WidgetRef ref,
    FileBrowserKey key,
    FileBrowserState state,
    RootfsFileEntry entry,
  ) {
    if (entry.isDirectory) {
      ref
          .read(fileBrowserProvider(key).notifier)
          .openDirectory(entry.relativePath);
      return;
    }
    if (entry.kind != RootfsFileKind.file) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持打开普通文件')),
      );
      return;
    }
    final size = entry.sizeBytes ?? 0;
    if (!isLikelyEditableTextFile(
      fileName: entry.name,
      sizeBytes: size,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该文件为二进制文件，不支持编辑')),
      );
      return;
    }
    final language = detectTextFileLanguage(entry.name);
    if (language == TextFileLanguage.toml) {
      // TOML 走专用编辑器（含语法诊断）。
      context.push(
        AppRoute.tomlEditor,
        extra: TomlEditorRouteArgs(
          scope: state.scope,
          relativePath: entry.relativePath,
        ),
      );
    } else {
      context.push(
        AppRoute.textEditor,
        extra: TextFileEditorRouteArgs(
          scope: state.scope,
          relativePath: entry.relativePath,
          language: language,
        ),
      );
    }
  }

  Future<void> _createDirectory(
    BuildContext context,
    WidgetRef ref,
    FileBrowserKey key,
    FileBrowserState state,
  ) async {
    final name = await showCreateDirectoryDialog(context);
    if (name == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fileBrowserProvider(key).notifier).createDirectory(name);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已创建目录'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } on RootfsFileException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _createTomlFile(
    BuildContext context,
    WidgetRef ref,
    FileBrowserKey key,
    FileBrowserState state,
  ) async {
    final name = await showCreateTomlFileDialog(context);
    if (name == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 通过 repository 创建空 TOML 文件
      final repo = ref.read(rootfsFileRepositoryProvider);
      await repo.writeTextDocument(
        scope: state.scope,
        path: state.path.child(name),
        text: '',
        hasUtf8Bom: false,
        writeMode: RootfsWriteMode.mustNotExist,
      );
      // 刷新列表
      ref.read(fileBrowserProvider(key).notifier).refresh();
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已创建文件'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } on RootfsFileException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    FileBrowserKey key,
    RootfsFileEntry entry,
  ) async {
    final newName = await showRenameDialog(context, entry.name);
    if (newName == null || newName == entry.name || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fileBrowserProvider(key).notifier).rename(entry, newName);
    } on RootfsFileException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FileBrowserKey key,
    RootfsFileEntry entry,
  ) async {
    final recursive = entry.isDirectory;
    final confirmed = await showDeleteConfirmDialog(
      context,
      entry.name,
      isDirectory: entry.isDirectory,
      recursive: recursive,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fileBrowserProvider(key).notifier)
          .delete(entry, recursive: recursive);
    } on RootfsFileException catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: scheme.error),
            const SizedBox(height: 16),
            Text('加载失败', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
