import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/file_manager/application/toml_editor_state.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_models.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_file_scope.dart';
import 'package:mofox_android/features/file_manager/domain/rootfs_relative_path.dart';
import 'package:mofox_android/features/file_manager/domain/toml_diagnostic.dart';

const _sha256Zero =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';

RootfsFileScope _scope() => RootfsFileScope(
      kind: RootfsFileScopeKind.repository,
      instanceId: 'inst-1',
      instanceRootPath: '/root/instances/inst-1',
    );

TomlEditorState _state({
  String loadedText = 'a = 1',
  String? text,
  TomlEditorLoadStatus status = TomlEditorLoadStatus.ready,
  bool isSaving = false,
  List<TomlDiagnostic> diagnostics = const [],
  RootfsRevision? revision,
}) {
  return TomlEditorState(
    scope: _scope(),
    path: const RootfsRelativePath.root(),
    loadStatus: status,
    loadedText: loadedText,
    text: text ?? loadedText,
    diagnostics: diagnostics,
    isSaving: isSaving,
    revision: revision,
  );
}

void main() {
  group('isDirty', () {
    test('false when text equals loadedText', () {
      expect(_state().isDirty, isFalse);
    });

    test('true when text differs from loadedText', () {
      expect(_state(text: 'a = 2').isDirty, isTrue);
    });
  });

  group('hasErrors', () {
    test('false when no diagnostics', () {
      expect(_state().hasErrors, isFalse);
    });

    test('false when only warnings', () {
      expect(
        _state(
          diagnostics: [
            const TomlDiagnostic(
              message: 'w',
              severity: TomlDiagnosticSeverity.warning,
            ),
          ],
        ).hasErrors,
        isFalse,
      );
    });

    test('true when error present', () {
      expect(
        _state(
          diagnostics: [
            const TomlDiagnostic(message: 'e'),
          ],
        ).hasErrors,
        isTrue,
      );
    });
  });

  group('canSave', () {
    test('false when not dirty', () {
      expect(_state().canSave, isFalse);
    });

    test('false when saving', () {
      expect(_state(text: 'b = 2', isSaving: true).canSave, isFalse);
    });

    test('false when has errors', () {
      expect(
        _state(
          text: 'b = 2',
          diagnostics: [const TomlDiagnostic(message: 'e')],
        ).canSave,
        isFalse,
      );
    });

    test('false when not ready', () {
      expect(
        _state(
          status: TomlEditorLoadStatus.loading,
          text: 'b = 2',
        ).canSave,
        isFalse,
      );
    });

    test('true when ready + dirty + no errors + not saving', () {
      expect(_state(text: 'b = 2').canSave, isTrue);
    });
  });

  group('copyWith', () {
    test('preserves revision when not provided', () {
      final s = _state(revision: RootfsRevision(_sha256Zero));
      final updated = s.copyWith(text: 'b = 2');
      expect(updated.revision, RootfsRevision(_sha256Zero));
    });

    test('clears revision when explicitly set to null', () {
      final s = _state(revision: RootfsRevision(_sha256Zero));
      final updated = s.copyWith(revision: null);
      expect(updated.revision, isNull);
    });

    test('clears saveError when explicitly set to null', () {
      final s = _state().copyWith(saveError: 'err');
      expect(s.saveError, 'err');
      final cleared = s.copyWith(saveError: null);
      expect(cleared.saveError, isNull);
    });

    test('updates loadStatus without touching nullable fields', () {
      final s = _state(revision: RootfsRevision(_sha256Zero))
          .copyWith(saveError: 'err');
      final updated = s.copyWith(loadStatus: TomlEditorLoadStatus.failed);
      expect(updated.loadStatus, TomlEditorLoadStatus.failed);
      expect(updated.revision, RootfsRevision(_sha256Zero));
      expect(updated.saveError, 'err');
    });
  });

  group('TomlEditorKey equality', () {
    test('equal when scope and path match', () {
      final scope = _scope();
      final a = TomlEditorKey(
        scope: scope,
        path: const RootfsRelativePath.root(),
      );
      final b = TomlEditorKey(
        scope: scope,
        path: const RootfsRelativePath.root(),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when path differs', () {
      final scope = _scope();
      final a = TomlEditorKey(
        scope: scope,
        path: const RootfsRelativePath.root(),
      );
      final b = TomlEditorKey(
        scope: scope,
        path: RootfsRelativePath(const <String>['config.toml']),
      );
      expect(a == b, isFalse);
    });
  });
}
