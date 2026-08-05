import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_bridge.dart';
import '../domain/rootfs_file_models.dart';
import '../domain/rootfs_file_scope.dart';
import '../domain/rootfs_relative_path.dart';

abstract interface class RootfsFileRepository {
  Future<RootfsDirectoryPage> listDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int limit = 200,
    String? cursor,
  });

  Future<RootfsFileEntry> statPath({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
  });

  Future<RootfsDocument> readTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int maxBytes = maxEditableTextBytes,
  });

  Future<RootfsWriteResult> writeTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String text,
    required bool hasUtf8Bom,
    required RootfsWriteMode writeMode,
    RootfsRevision? expectedRevision,
  });

  Future<void> createDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath parentPath,
    required String name,
  });

  Future<void> renameEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String newName,
  });

  Future<void> deleteEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required bool recursive,
  });
}

class RuntimeRootfsFileRepository implements RootfsFileRepository {
  const RuntimeRootfsFileRepository(this._runtime);

  final RuntimeBridge _runtime;

  @override
  Future<RootfsDirectoryPage> listDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int limit = 200,
    String? cursor,
  }) =>
      _runtime.listDirectory(
        scope: scope,
        path: path,
        limit: limit,
        cursor: cursor,
      );

  @override
  Future<RootfsFileEntry> statPath({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
  }) =>
      _runtime.statPath(scope: scope, path: path);

  @override
  Future<RootfsDocument> readTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int maxBytes = maxEditableTextBytes,
  }) =>
      _runtime.readTextDocument(
        scope: scope,
        path: path,
        maxBytes: maxBytes,
      );

  @override
  Future<RootfsWriteResult> writeTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String text,
    required bool hasUtf8Bom,
    required RootfsWriteMode writeMode,
    RootfsRevision? expectedRevision,
  }) =>
      _runtime.writeTextDocument(
        scope: scope,
        path: path,
        text: text,
        hasUtf8Bom: hasUtf8Bom,
        writeMode: writeMode,
        expectedRevision: expectedRevision,
      );

  @override
  Future<void> createDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath parentPath,
    required String name,
  }) =>
      _runtime.createDirectory(
        scope: scope,
        parentPath: parentPath,
        name: name,
      );

  @override
  Future<void> renameEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String newName,
  }) =>
      _runtime.renameEntry(scope: scope, path: path, newName: newName);

  @override
  Future<void> deleteEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required bool recursive,
  }) =>
      _runtime.deleteEntry(
        scope: scope,
        path: path,
        recursive: recursive,
      );
}

final rootfsFileRepositoryProvider = Provider<RootfsFileRepository>(
  (ref) => RuntimeRootfsFileRepository(ref.watch(runtimeBridgeProvider)),
);

const int maxEditableTextBytes = 1024 * 1024;
const int liveHighlightTextBytes = 256 * 1024;
