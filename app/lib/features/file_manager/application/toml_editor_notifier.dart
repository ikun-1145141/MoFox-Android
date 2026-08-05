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
        // 冲突：刷新以获取最新内容，让用户决定是否覆盖。
        await _load();
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
        RootfsFileErrorCode.conflict => '文件已被外部修改，已重新加载最新内容',
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
