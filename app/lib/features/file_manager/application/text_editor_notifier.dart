import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/rootfs_file_exception.dart';
import '../domain/rootfs_file_models.dart';
import '../domain/rootfs_file_scope.dart';
import '../domain/rootfs_relative_path.dart';
import '../domain/text_file_language.dart';
import 'rootfs_file_repository.dart';

/// 文本编辑器加载阶段。
enum TextEditorLoadStatus { idle, loading, ready, notFound, failed }

/// 通用文本编辑器状态。
class TextEditorState {
  const TextEditorState({
    required this.scope,
    required this.path,
    required this.language,
    required this.loadStatus,
    this.loadedText = '',
    this.text = '',
    this.hasUtf8Bom = false,
    this.newlineStyle = RootfsNewlineStyle.lf,
    this.hasFinalNewline = true,
    this.revision,
    this.isSaving = false,
    this.saveError,
    this.lastSavedAt,
  });

  final RootfsFileScope scope;
  final RootfsRelativePath path;
  final TextFileLanguage language;
  final TextEditorLoadStatus loadStatus;

  final String loadedText;
  final String text;
  final bool hasUtf8Bom;
  final RootfsNewlineStyle newlineStyle;
  final bool hasFinalNewline;
  final RootfsRevision? revision;

  final bool isSaving;
  final String? saveError;
  final DateTime? lastSavedAt;

  bool get isDirty => text != loadedText;

  bool get canSave =>
      loadStatus == TextEditorLoadStatus.ready && isDirty && !isSaving;

  TextEditorState copyWith({
    TextEditorLoadStatus? loadStatus,
    String? loadedText,
    String? text,
    bool? hasUtf8Bom,
    RootfsNewlineStyle? newlineStyle,
    bool? hasFinalNewline,
    Object? revision = _sentinel,
    bool? isSaving,
    Object? saveError = _sentinel,
    DateTime? lastSavedAt,
  }) =>
      TextEditorState(
        scope: scope,
        path: path,
        language: language,
        loadStatus: loadStatus ?? this.loadStatus,
        loadedText: loadedText ?? this.loadedText,
        text: text ?? this.text,
        hasUtf8Bom: hasUtf8Bom ?? this.hasUtf8Bom,
        newlineStyle: newlineStyle ?? this.newlineStyle,
        hasFinalNewline: hasFinalNewline ?? this.hasFinalNewline,
        revision: identical(revision, _sentinel)
            ? this.revision
            : revision as RootfsRevision?,
        isSaving: isSaving ?? this.isSaving,
        saveError: identical(saveError, _sentinel)
            ? this.saveError
            : saveError as String?,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      );
}

const Object _sentinel = Object();

/// 文本编辑器 family 参数。
class TextEditorKey {
  const TextEditorKey({required this.scope, required this.path});

  final RootfsFileScope scope;
  final RootfsRelativePath path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextEditorKey && scope == other.scope && path == other.path;

  @override
  int get hashCode => Object.hash(scope, path);
}

/// 通用文本编辑器 Notifier。
///
/// 与 TOML 编辑器类似的加载/保存/CAS 冲突流程，但不做语法诊断（通用文本无
/// 统一校验器）。
class TextEditorNotifier
    extends AutoDisposeFamilyNotifier<TextEditorState, TextEditorKey> {
  var _generation = 0;

  RootfsFileRepository get _repository =>
      ref.read(rootfsFileRepositoryProvider);

  @override
  TextEditorState build(TextEditorKey arg) {
    ref.onDispose(() {
      _generation++;
    });
    Future<void>.microtask(_load);
    return TextEditorState(
      scope: arg.scope,
      path: arg.path,
      language: detectTextFileLanguage(arg.path.name),
      loadStatus: TextEditorLoadStatus.loading,
    );
  }

  Future<void> reload() => _load();

  void updateText(String text) {
    state = state.copyWith(text: text, saveError: null);
  }

  Future<void> save() async {
    if (!state.canSave) return;
    final generation = _generation;
    state = state.copyWith(isSaving: true, saveError: null);
    try {
      final result = await _repository.writeTextDocument(
        scope: state.scope,
        path: state.path,
        text: state.text,
        hasUtf8Bom: state.hasUtf8Bom,
        writeMode: RootfsWriteMode.mustExist,
        expectedRevision: state.revision,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        loadedText: state.text,
        revision: result.revision,
        isSaving: false,
        lastSavedAt: result.modifiedAt,
      );
    } on RootfsFileException catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(isSaving: false, saveError: error.message);
      if (error.code == RootfsFileErrorCode.conflict) {
        await _load();
      }
      rethrow;
    } on Object catch (error) {
      if (generation != _generation) return;
      appLogger.e('text_editor: save failed', error: error);
      state = state.copyWith(
        isSaving: false,
        saveError: '保存失败：$error',
      );
      rethrow;
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    state = state.copyWith(
      loadStatus: TextEditorLoadStatus.loading,
      saveError: null,
    );
    try {
      final doc = await _repository.readTextDocument(
        scope: state.scope,
        path: state.path,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        loadedText: doc.text,
        text: doc.text,
        hasUtf8Bom: doc.hasUtf8Bom,
        newlineStyle: doc.newlineStyle,
        hasFinalNewline: doc.hasFinalNewline,
        revision: doc.revision,
        loadStatus: TextEditorLoadStatus.ready,
      );
    } on RootfsFileException catch (error) {
      if (generation != _generation) return;
      final status = error.code == RootfsFileErrorCode.notFound
          ? TextEditorLoadStatus.notFound
          : TextEditorLoadStatus.failed;
      state = state.copyWith(
        loadStatus: status,
        saveError: error.message,
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      appLogger.e('text_editor: load failed', error: error);
      state = state.copyWith(
        loadStatus: TextEditorLoadStatus.failed,
        saveError: '加载失败：$error',
      );
    }
  }
}

final textEditorProvider = NotifierProvider.autoDispose
    .family<TextEditorNotifier, TextEditorState, TextEditorKey>(
  TextEditorNotifier.new,
);
