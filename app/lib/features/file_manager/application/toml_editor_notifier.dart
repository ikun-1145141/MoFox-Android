import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/rootfs_file_exception.dart';
import '../domain/rootfs_file_models.dart';
import 'rootfs_file_repository.dart';
import 'toml_editor_state.dart';
import 'toml_validator.dart';

/// TOML 编辑器 Notifier。
///
/// 职责：
/// 1. 加载文件文本 + revision。
/// 2. 文本变更时增量更新诊断（防抖）。
/// 3. 保存：带 expectedRevision CAS，冲突时刷新并提示。
///
/// generation 机制：当 family 重建或 disposed 时递增，丢弃过期异步响应。
class TomlEditorNotifier
    extends AutoDisposeFamilyNotifier<TomlEditorState, TomlEditorKey> {
  var _generation = 0;
  Timer? _diagnosticDebounce;

  RootfsFileRepository get _repository =>
      ref.read(rootfsFileRepositoryProvider);

  static const Duration _diagnosticDelay = Duration(milliseconds: 250);

  @override
  TomlEditorState build(TomlEditorKey arg) {
    ref.onDispose(() {
      _generation++;
      _diagnosticDebounce?.cancel();
    });
    Future<void>.microtask(_load);
    return TomlEditorState(
      scope: arg.scope,
      path: arg.path,
      loadStatus: TomlEditorLoadStatus.loading,
    );
  }

  Future<void> reload() => _load();

  /// 用户文本变更。
  void updateText(String text) {
    state = state.copyWith(text: text, saveError: null);
    _scheduleDiagnostics(text);
  }

  /// 手动触发诊断（如失焦时）。
  void refreshDiagnostics() {
    _diagnosticDebounce?.cancel();
    _computeDiagnostics(state.text);
  }

  /// 放弃当前草稿，恢复为最近一次从磁盘读取的内容。
  ///
  /// 冲突后 [loadedText] 是外部程序的最新版本，[text] 仍保留
  /// 用户草稿；只有用户明确选择重新加载时才调用此方法。
  void discardLocalChanges() {
    _diagnosticDebounce?.cancel();
    state = state.copyWith(text: state.loadedText, saveError: null);
    _computeDiagnostics(state.loadedText);
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
      final friendly = _friendlySaveError(error);
      state = state.copyWith(isSaving: false, saveError: friendly);
      if (error.code == RootfsFileErrorCode.conflict) {
        await _refreshRevisionAfterConflict(
          localText: state.text,
          generation: generation,
        );
      }
      rethrow;
    } on Object catch (error) {
      if (generation != _generation) return;
      appLogger.e('toml_editor: save failed', error: error);
      state = state.copyWith(
        isSaving: false,
        saveError: '保存失败：$error',
      );
      rethrow;
    }
  }

  /// 冲突时更新磁盘基线和 revision，但绝不覆盖用户的本地草稿。
  ///
  /// 这样页面与 Provider 始终看到同一份待保存文本，用户可以
  /// 选择放弃草稿，或再次保存并对新 revision 做第二次 CAS。
  Future<void> _refreshRevisionAfterConflict({
    required String localText,
    required int generation,
  }) async {
    try {
      final doc = await _repository.readTextDocument(
        scope: state.scope,
        path: state.path,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        loadedText: doc.text,
        text: localText,
        hasUtf8Bom: doc.hasUtf8Bom,
        newlineStyle: doc.newlineStyle,
        hasFinalNewline: doc.hasFinalNewline,
        revision: doc.revision,
        loadStatus: TomlEditorLoadStatus.ready,
        isSaving: false,
        saveError: '文件已被外部修改，你的本地草稿已保留',
      );
    } on Object catch (refreshError) {
      if (generation != _generation) return;
      appLogger.e(
        'toml_editor: failed to refresh conflict revision',
        error: refreshError,
      );
      state = state.copyWith(
        text: localText,
        isSaving: false,
        saveError: '文件已被外部修改；本地草稿已保留，但读取新版本失败',
      );
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _diagnosticDebounce?.cancel();
    state = state.copyWith(
      loadStatus: TomlEditorLoadStatus.loading,
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
        loadStatus: TomlEditorLoadStatus.ready,
      );
      _computeDiagnostics(doc.text);
    } on RootfsFileException catch (error) {
      if (generation != _generation) return;
      if (error.code == RootfsFileErrorCode.notFound) {
        state = state.copyWith(loadStatus: TomlEditorLoadStatus.notFound);
      } else {
        state = state.copyWith(
          loadStatus: TomlEditorLoadStatus.failed,
          saveError: _friendlySaveError(error),
        );
      }
    } on Object catch (error) {
      if (generation != _generation) return;
      appLogger.e('toml_editor: load failed', error: error);
      state = state.copyWith(
        loadStatus: TomlEditorLoadStatus.failed,
        saveError: '加载失败：$error',
      );
    }
  }

  void _scheduleDiagnostics(String text) {
    _diagnosticDebounce?.cancel();
    _diagnosticDebounce = Timer(_diagnosticDelay, () {
      _computeDiagnostics(text);
    });
  }

  void _computeDiagnostics(String text) {
    final generation = _generation;
    final diagnostics = const TomlValidator().validate(text);
    if (generation != _generation) return;
    state = state.copyWith(diagnostics: diagnostics);
  }

  String _friendlySaveError(RootfsFileException error) => switch (error.code) {
        RootfsFileErrorCode.conflict => '文件已被外部修改，本地草稿已保留',
        RootfsFileErrorCode.notFound => '文件已不存在',
        RootfsFileErrorCode.permissionDenied => '没有写权限',
        RootfsFileErrorCode.fileTooLarge => '文件超过大小上限',
        RootfsFileErrorCode.busy => '文件服务繁忙，请稍后重试',
        _ => error.message,
      };
}

final tomlEditorProvider = NotifierProvider.autoDispose
    .family<TomlEditorNotifier, TomlEditorState, TomlEditorKey>(
  TomlEditorNotifier.new,
);
