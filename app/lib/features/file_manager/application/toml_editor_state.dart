import '../domain/rootfs_file_models.dart';
import '../domain/rootfs_file_scope.dart';
import '../domain/rootfs_relative_path.dart';
import '../domain/toml_diagnostic.dart';

/// TOML 编辑器加载阶段。
enum TomlEditorLoadStatus { idle, loading, ready, notFound, failed }

/// TOML 编辑器的不可变状态。
///
/// 文本内容分两份：
/// - [loadedText]：从原生层加载的原始文本（含 BOM 去除后），用于 dirty 判定。
/// - [text]：用户当前编辑的文本（含未保存修改）。
///
/// [revision] 是加载时的文件 revision（sha256），保存时作为 expectedRevision 传给
/// 原生层做 CAS；保存成功后更新为新 revision。
class TomlEditorState {
  const TomlEditorState({
    required this.scope,
    required this.path,
    required this.loadStatus,
    this.loadedText = '',
    this.text = '',
    this.hasUtf8Bom = false,
    this.newlineStyle = RootfsNewlineStyle.lf,
    this.hasFinalNewline = true,
    this.revision,
    this.diagnostics = const <TomlDiagnostic>[],
    this.isSaving = false,
    this.saveError,
    this.lastSavedAt,
  });

  final RootfsFileScope scope;
  final RootfsRelativePath path;
  final TomlEditorLoadStatus loadStatus;

  final String loadedText;
  final String text;
  final bool hasUtf8Bom;
  final RootfsNewlineStyle newlineStyle;
  final bool hasFinalNewline;
  final RootfsRevision? revision;

  final List<TomlDiagnostic> diagnostics;
  final bool isSaving;
  final String? saveError;
  final DateTime? lastSavedAt;

  /// 文本是否有未保存修改。
  bool get isDirty => text != loadedText;

  /// 是否存在错误级诊断。
  bool get hasErrors => diagnostics.any(
        (d) => d.severity == TomlDiagnosticSeverity.error,
      );

  bool get canSave =>
      loadStatus == TomlEditorLoadStatus.ready &&
      isDirty &&
      !isSaving &&
      !hasErrors;

  TomlEditorState copyWith({
    TomlEditorLoadStatus? loadStatus,
    String? loadedText,
    String? text,
    bool? hasUtf8Bom,
    RootfsNewlineStyle? newlineStyle,
    bool? hasFinalNewline,
    Object? revision = _sentinel,
    List<TomlDiagnostic>? diagnostics,
    bool? isSaving,
    Object? saveError = _sentinel,
    DateTime? lastSavedAt,
  }) =>
      TomlEditorState(
        scope: scope,
        path: path,
        loadStatus: loadStatus ?? this.loadStatus,
        loadedText: loadedText ?? this.loadedText,
        text: text ?? this.text,
        hasUtf8Bom: hasUtf8Bom ?? this.hasUtf8Bom,
        newlineStyle: newlineStyle ?? this.newlineStyle,
        hasFinalNewline: hasFinalNewline ?? this.hasFinalNewline,
        revision: identical(revision, _sentinel)
            ? this.revision
            : revision as RootfsRevision?,
        diagnostics: diagnostics ?? this.diagnostics,
        isSaving: isSaving ?? this.isSaving,
        saveError: identical(saveError, _sentinel)
            ? this.saveError
            : saveError as String?,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      );
}

const Object _sentinel = Object();

/// TOML 编辑器 Notifier 的 family 参数。
class TomlEditorKey {
  const TomlEditorKey({required this.scope, required this.path});

  final RootfsFileScope scope;
  final RootfsRelativePath path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TomlEditorKey && scope == other.scope && path == other.path;

  @override
  int get hashCode => Object.hash(scope, path);
}
