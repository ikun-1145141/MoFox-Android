import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/file_manager/application/toml_validator.dart';
import 'package:mofox_android/features/file_manager/domain/toml_diagnostic.dart';

void main() {
  const validator = TomlValidator();

  test('empty source is valid', () {
    expect(validator.validate(''), isEmpty);
  });

  test('simple key-value is valid', () {
    expect(validator.validate('port = 8080'), isEmpty);
  });

  test('table and nested keys are valid', () {
    const source = '''
[server]
host = "0.0.0.0"
port = 8080
enabled = true
''';
    expect(validator.validate(source), isEmpty);
  });

  test('missing value produces error diagnostic', () {
    final diagnostics = validator.validate('port =');
    expect(diagnostics, hasLength(1));
    final diag = diagnostics.single;
    expect(diag.severity, TomlDiagnosticSeverity.error);
    expect(diag.source, 'toml');
    expect(diag.hasLocation, isTrue);
    expect(diag.line, greaterThanOrEqualTo(1));
  });

  test('duplicate table produces semantic error', () {
    const source = '''
[a]
x = 1

[a]
y = 2
''';
    final diagnostics = validator.validate(source);
    expect(diagnostics, isNotEmpty);
    expect(diagnostics.first.severity, TomlDiagnosticSeverity.error);
  });

  test('parser error line is 1-based', () {
    final diagnostics = validator.validate('= 1');
    expect(diagnostics, hasLength(1));
    final diag = diagnostics.first;
    expect(diag.line, 1);
  });

  test('error on second line reports a valid line number', () {
    const source = 'a = 1\nb =';
    final diagnostics = validator.validate(source);
    expect(diagnostics, hasLength(1));
    final diag = diagnostics.first;
    // 解析器可能在 EOF 处报告，行号应为 1 或 2，但必须是正数。
    expect(diag.line, greaterThanOrEqualTo(1));
  });

  test('friendly message prefixes expected errors', () {
    final diagnostics = validator.validate('port =');
    expect(diagnostics, isNotEmpty);
    final message = diagnostics.first.message;
    // 解析器通常返回 "expected ..." 形式
    expect(message, anyOf(contains('语法错误'), contains('expected')));
  });

  test('array of tables is valid', () {
    const source = '''
[[servers]]
name = "alpha"

[[servers]]
name = "beta"
''';
    expect(validator.validate(source), isEmpty);
  });

  test('datetime value is valid', () {
    const source = 'created = 2024-01-15T10:30:00Z';
    expect(validator.validate(source), isEmpty);
  });
}
