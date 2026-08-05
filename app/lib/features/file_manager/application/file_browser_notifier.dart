import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/rootfs_file_exception.dart';
import '../domain/rootfs_file_models.dart';
import '../domain/rootfs_file_scope.dart';
import '../domain/rootfs_relative_path.dart';
import 'file_browser_state.dart';
import 'rootfs_file_repository.dart';

class FileBrowserNotifier
    extends AutoDisposeFamilyNotifier<FileBrowserState, FileBrowserKey> {
  var _generation = 0;
  var _isDisposed = false;

  RootfsFileRepository get _repository =>
      ref.read(rootfsFileRepositoryProvider);

  @override
  FileBrowserState build(FileBrowserKey arg) {
    final initial = FileBrowserState.initial(arg);
    ref.onDispose(() {
      _isDisposed = true;
      _generation++;
    });
    Future<void>.microtask(() async {
      if (!_isDisposed) {
        await _load(arg.scope, arg.initialPath);
      }
    });
    return initial;
  }

  Future<void> refresh() => _load(state.scope, state.path);

  Future<void> openDirectory(RootfsRelativePath path) =>
      _load(state.scope, path);

  Future<void> goUp() async {
    if (state.path.isRoot) return;
    await _load(state.scope, state.path.parent);
  }

  Future<void> switchScope(RootfsFileScopeKind kind) async {
    if (state.scope.kind == kind) return;
    await _load(state.scope.withKind(kind), const RootfsRelativePath.root());
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.isLoading || state.isLoadingMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, errorMessage: null);
    try {
      final page = await _repository.listDirectory(
        scope: state.scope,
        path: state.path,
        cursor: cursor,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        entries: List<RootfsFileEntry>.unmodifiable(
          <RootfsFileEntry>[...state.entries, ...page.entries],
        ),
        nextCursor: page.nextCursor,
        isLoadingMore: false,
      );
    } on RootfsFileException catch (error) {
      if (generation != _generation) return;
      if (error.code == RootfsFileErrorCode.staleListing) {
        await refresh();
        return;
      }
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: _friendlyFileError(error),
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: '加载更多失败：$error',
      );
    }
  }

  Future<void> createDirectory(String name) => _runMutation(
        () => _repository.createDirectory(
          scope: state.scope,
          parentPath: state.path,
          name: name,
        ),
      );

  Future<void> rename(RootfsFileEntry entry, String newName) => _runMutation(
        () => _repository.renameEntry(
          scope: state.scope,
          path: entry.relativePath,
          newName: newName,
        ),
      );

  Future<void> delete(RootfsFileEntry entry, {required bool recursive}) =>
      _runMutation(
        () => _repository.deleteEntry(
          scope: state.scope,
          path: entry.relativePath,
          recursive: recursive,
        ),
      );

  Future<void> _load(
    RootfsFileScope scope,
    RootfsRelativePath path,
  ) async {
    final generation = ++_generation;
    state = state.copyWith(
      scope: scope,
      path: path,
      entries: const <RootfsFileEntry>[],
      nextCursor: null,
      isLoading: true,
      isLoadingMore: false,
      errorMessage: null,
    );
    try {
      final page = await _repository.listDirectory(scope: scope, path: path);
      if (generation != _generation) return;
      state = state.copyWith(
        entries: List<RootfsFileEntry>.unmodifiable(page.entries),
        nextCursor: page.nextCursor,
        isLoading: false,
      );
    } on RootfsFileException catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _friendlyFileError(error),
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: '读取目录失败：$error',
      );
    }
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    if (state.isMutating) return;
    state = state.copyWith(isMutating: true, errorMessage: null);
    try {
      await action();
      await refresh();
    } on RootfsFileException catch (error) {
      state = state.copyWith(
        isMutating: false,
        errorMessage: _friendlyFileError(error),
      );
      rethrow;
    } on Object catch (error) {
      state = state.copyWith(
        isMutating: false,
        errorMessage: '文件操作失败：$error',
      );
      rethrow;
    } finally {
      if (state.isMutating) {
        state = state.copyWith(isMutating: false);
      }
    }
  }
}

String _friendlyFileError(RootfsFileException error) => switch (error.code) {
      RootfsFileErrorCode.scopeNotFound => '实例文件目录尚不可用',
      RootfsFileErrorCode.rootfsNotReady => '运行环境尚未安装完成',
      RootfsFileErrorCode.notFound => '文件或目录已不存在，请刷新',
      RootfsFileErrorCode.alreadyExists => '同名文件或目录已存在',
      RootfsFileErrorCode.permissionDenied => '没有权限执行此操作',
      RootfsFileErrorCode.readOnlyScope => '当前目录为只读',
      RootfsFileErrorCode.directoryNotEmpty => '目录非空，需要确认递归删除',
      RootfsFileErrorCode.symlinkNotAllowed => '不允许进入符号链接',
      RootfsFileErrorCode.fileTooLarge => '文件超过编辑大小上限',
      RootfsFileErrorCode.invalidUtf8 => '文件不是有效的 UTF-8 文本',
      RootfsFileErrorCode.busy => '文件服务繁忙，请稍后重试',
      _ => error.message,
    };

final fileBrowserProvider = NotifierProvider.autoDispose
    .family<FileBrowserNotifier, FileBrowserState, FileBrowserKey>(
  FileBrowserNotifier.new,
);
