import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/file_manager/application/rootfs_file_repository.dart';
import 'package:mofox_android/features/file_manager/application/text_editor_notifier.dart';
import 'package:mofox_android/features/file_manager/application/toml_editor_notifier.dart';
import 'package:mofox_android/features/file_manager/application/toml_editor_state.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_exception.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_models.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_scope.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_relative_path.dart';

void main() {
  const scope = RootfsFileScope(
    kind: RootfsFileScopeKind.repository,
    instanceId: 'instance-1',
    instanceRootPath: '/root/mofox',
  );
  final path = RootfsRelativePath(<String>['config.toml']);

  test('TOML conflict keeps draft and refreshes the disk revision', () async {
    final repository = _ConflictRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        rootfsFileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final key = TomlEditorKey(scope: scope, path: path);
    final subscription = container.listen(
      tomlEditorProvider(key),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _waitUntil(
      () =>
          container.read(tomlEditorProvider(key)).loadStatus ==
          TomlEditorLoadStatus.ready,
    );
    final notifier = container.read(tomlEditorProvider(key).notifier);
    notifier.updateText('local = true\n');

    await expectLater(
      notifier.save(),
      throwsA(
        isA<RootfsFileException>().having(
          (error) => error.code,
          'code',
          RootfsFileErrorCode.conflict,
        ),
      ),
    );

    final conflicted = container.read(tomlEditorProvider(key));
    expect(conflicted.text, 'local = true\n');
    expect(conflicted.loadedText, 'remote = true\n');
    expect(conflicted.revision, _revision('2'));
    expect(conflicted.isDirty, isTrue);
    expect(conflicted.saveError, contains('草稿已保留'));

    notifier.discardLocalChanges();
    final discarded = container.read(tomlEditorProvider(key));
    expect(discarded.text, 'remote = true\n');
    expect(discarded.isDirty, isFalse);
  });

  test('plain text conflict keeps draft and refreshes the disk revision',
      () async {
    final repository = _ConflictRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        rootfsFileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final key = TextEditorKey(scope: scope, path: path);
    final subscription = container.listen(
      textEditorProvider(key),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _waitUntil(
      () =>
          container.read(textEditorProvider(key)).loadStatus ==
          TextEditorLoadStatus.ready,
    );
    final notifier = container.read(textEditorProvider(key).notifier);
    notifier.updateText('my draft\n');

    await expectLater(notifier.save(), throwsA(isA<RootfsFileException>()));

    final conflicted = container.read(textEditorProvider(key));
    expect(conflicted.text, 'my draft\n');
    expect(conflicted.loadedText, 'remote = true\n');
    expect(conflicted.revision, _revision('2'));
    expect(conflicted.isDirty, isTrue);

    await notifier.save();
    final overwritten = container.read(textEditorProvider(key));
    expect(repository.expectedRevisions.last, _revision('2'));
    expect(overwritten.loadedText, 'my draft\n');
    expect(overwritten.revision, _revision('3'));
    expect(overwritten.isDirty, isFalse);
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for provider state');
}

RootfsRevision _revision(String digit) => RootfsRevision(
      'sha256:${List<String>.filled(64, digit).join()}',
    );

RootfsDocument _document(String text, RootfsRevision revision) =>
    RootfsDocument(
      text: text,
      hasUtf8Bom: false,
      newlineStyle: RootfsNewlineStyle.lf,
      hasFinalNewline: true,
      sizeBytes: text.length,
      modifiedAt: DateTime(2026),
      revision: revision,
    );

class _ConflictRepository implements RootfsFileRepository {
  var _readCount = 0;
  var _writeCount = 0;
  final List<RootfsRevision?> expectedRevisions = <RootfsRevision?>[];

  @override
  Future<RootfsDocument> readTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int maxBytes = maxEditableTextBytes,
  }) async {
    _readCount++;
    return _readCount == 1
        ? _document('original = true\n', _revision('1'))
        : _document('remote = true\n', _revision('2'));
  }

  @override
  Future<RootfsWriteResult> writeTextDocument({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String text,
    required bool hasUtf8Bom,
    required RootfsWriteMode writeMode,
    RootfsRevision? expectedRevision,
  }) async {
    _writeCount++;
    expectedRevisions.add(expectedRevision);
    if (_writeCount == 1) {
      throw const RootfsFileException(
        code: RootfsFileErrorCode.conflict,
        message: 'revision changed',
      );
    }
    return RootfsWriteResult(
      revision: _revision('3'),
      sizeBytes: text.length,
      modifiedAt: DateTime(2026, 1, 2),
    );
  }

  @override
  Future<void> createDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath parentPath,
    required String name,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required bool recursive,
  }) =>
      throw UnimplementedError();

  @override
  Future<RootfsDirectoryPage> listDirectory({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    int limit = 200,
    String? cursor,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> renameEntry({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
    required String newName,
  }) =>
      throw UnimplementedError();

  @override
  Future<RootfsFileEntry> statPath({
    required RootfsFileScope scope,
    required RootfsRelativePath path,
  }) =>
      throw UnimplementedError();
}
