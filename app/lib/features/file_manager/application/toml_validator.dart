import 'package:toml/toml.dart';

import '../domain/toml_diagnostic.dart';

/// TOML 合法性验证器。
///
/// 使用 `toml` 包的 [TomlDocument.parse] 进行完整语法解析，捕获
/// [TomlParserException]（带行列信息）和其他 [TomlException]（语义级，无位置）。
/// 异常捕获顺序遵循 petitparser/toml 的类型层级：
/// `TomlParserException` 实现 `FormatException`，必须先捕获；其他
/// `TomlException` 子类随后捕获；最后兜底未知异常。
class TomlValidator {
  const TomlValidator();

  /// 解析 [source] 并返回诊断列表；空列表表示合法。
  ///
  /// 空文档视为合法（返回空列表），避免无意义报错。
  List<TomlDiagnostic> validate(String source) {
    if (source.isEmpty) return const <TomlDiagnostic>[];

    try {
      // 触发完整解析（含语义阶段）；toMap() 会遍历 AST 并可能抛出
      // TomlNotATableException、TomlRedefinitionException 等语义异常。
      TomlDocument.parse(source).toMap();
      return const <TomlDiagnostic>[];
    } on TomlParserException catch (error) {
      return <TomlDiagnostic>[
        TomlDiagnostic(
          message: _friendlyParserMessage(error.message),
          line: error.line,
          column: error.column,
          length: 1,
        ),
      ];
    } on TomlException catch (error) {
      // 语义级异常通常没有精确的源位置。
      return <TomlDiagnostic>[
        TomlDiagnostic(
          message: error.message,
        ),
      ];
    } on FormatException catch (error) {
      // 理论上 TomlParserException 已覆盖，但防御性兜底。
      return <TomlDiagnostic>[
        TomlDiagnostic(
          message: error.message.isNotEmpty ? error.message : 'TOML 格式错误',
        ),
      ];
    } catch (error) {
      return <TomlDiagnostic>[
        TomlDiagnostic(
          message: '解析失败：$error',
        ),
      ];
    }
  }

  /// 将 petitparser 原始消息转成更友好的中文提示。
  String _friendlyParserMessage(String raw) {
    final message = raw.trim();
    if (message.isEmpty) return 'TOML 语法错误';
    if (message.isEmpty) return 'TOML 语法错误';
    // 常见 petitparser 消息形如 "expected ..." 或 "end of input expected"。
    // 保留原始技术信息，但前置中文说明。
    if (message.startsWith('expected')) {
      return '语法错误：$message';
    }
    return message;
  }
}
