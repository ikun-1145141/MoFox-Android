import '../domain/rootfs_file_models.dart';
import '../domain/rootfs_file_scope.dart';
import '../domain/rootfs_relative_path.dart';

class FileBrowserKey {
  const FileBrowserKey({required this.scope, required this.initialPath});

  final RootfsFileScope scope;
  final RootfsRelativePath initialPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileBrowserKey &&
          scope == other.scope &&
          initialPath == other.initialPath;

  @override
  int get hashCode => Object.hash(scope, initialPath);
}

class FileBrowserState {
  const FileBrowserState({
    required this.scope,
    required this.path,
    required this.entries,
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isMutating = false,
    this.errorMessage,
  });

  factory FileBrowserState.initial(FileBrowserKey key) => FileBrowserState(
        scope: key.scope,
        path: key.initialPath,
        entries: const <RootfsFileEntry>[],
        isLoading: true,
      );

  final RootfsFileScope scope;
  final RootfsRelativePath path;
  final List<RootfsFileEntry> entries;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isMutating;
  final String? errorMessage;

  bool get hasMore => nextCursor != null;

  FileBrowserState copyWith({
    RootfsFileScope? scope,
    RootfsRelativePath? path,
    List<RootfsFileEntry>? entries,
    Object? nextCursor = _sentinel,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isMutating,
    Object? errorMessage = _sentinel,
  }) =>
      FileBrowserState(
        scope: scope ?? this.scope,
        path: path ?? this.path,
        entries: entries ?? this.entries,
        nextCursor: identical(nextCursor, _sentinel)
            ? this.nextCursor
            : nextCursor as String?,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        isMutating: isMutating ?? this.isMutating,
        errorMessage: identical(errorMessage, _sentinel)
            ? this.errorMessage
            : errorMessage as String?,
      );
}

const Object _sentinel = Object();
