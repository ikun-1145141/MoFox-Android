/// TOML 诊断严重级别。
enum TomlDiagnosticSeverity {
  error,
  warning,
  info;

  String get displayName => switch (this) {
        TomlDiagnosticSeverity.error => '错误',
        TomlDiagnosticSeverity.warning => '警告',
        TomlDiagnosticSeverity.info => '提示',
      };
}

/// TOML 文本诊断。
///
/// 位置字段使用 1 基行列（显示用），`length` 为 UTF-16 code-unit 长度。
/// 当诊断没有精确源位置（如语义级异常）时，`line`/`column`/`length` 为 null。
class TomlDiagnostic {
  const TomlDiagnostic({
    required this.message,
    this.severity = TomlDiagnosticSeverity.error,
    this.source = 'toml',
    this.line,
    this.column,
    this.length,
  });

  final String message;
  final TomlDiagnosticSeverity severity;
  final String source;

  /// 1 基行号，null 表示全局诊断。
  final int? line;

  /// 1 基列号，null 表示无精确列。
  final int? column;

  /// 诊断覆盖长度（UTF-16 code units），null 时默认为 1。
  final int? length;

  bool get hasLocation => line != null;

  String get displayLocation {
    final currentLine = line;
    if (currentLine == null) return '';
    final currentColumn = column;
    return currentColumn == null
        ? '第 $currentLine 行'
        : '第 $currentLine 行，第 $currentColumn 列';
  }
}
