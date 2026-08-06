import 'package:flutter/material.dart';

import '../../application/python_tokenizer.dart';
import '../../application/toml_tokenizer.dart';
import '../../domain/text_file_language.dart';

/// 通用文本编辑控制器。
///
/// 根据 [language] 选择对应的高亮策略：
/// - [TextFileLanguage.toml]：复用 [TomlTokenizer]；
/// - [TextFileLanguage.python]：使用 [PythonTokenizer]；
/// - [TextFileLanguage.structured]：键值对风格的轻量高亮；
/// - [TextFileLanguage.markdown] / [TextFileLanguage.plain]：无高亮。
///
/// 文本未变化时复用上次结果，避免每次 build 重复 tokenize。
class TextFileEditingController extends TextEditingController {
  TextFileEditingController({
    required this.language,
    super.text,
  });

  final TextFileLanguage language;

  static const TomlTokenizer _tomlTokenizer = TomlTokenizer();
  static const PythonTokenizer _pythonTokenizer = PythonTokenizer();

  String? _lastSource;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (text.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    if (_lastSource == text) {
      // 复用：直接返回无分段的纯文本，避免重复扫描。
      return TextSpan(text: text, style: style);
    }
    _lastSource = text;

    switch (language) {
      case TextFileLanguage.toml:
        return _buildToml(text, context, style);
      case TextFileLanguage.python:
        return _buildPython(text, context, style);
      case TextFileLanguage.structured:
        return _buildStructured(text, context, style);
      case TextFileLanguage.markdown:
      case TextFileLanguage.plain:
        return TextSpan(text: text, style: style);
    }
  }

  TextSpan _buildToml(String text, BuildContext context, TextStyle? style) {
    final tokenization = _tomlTokenizer.tokenize(text);
    final scheme = Theme.of(context).colorScheme;
    if (tokenization.tokens.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final token in tokenization.tokens) {
      if (token.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, token.start),
          style: style,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(token.start, token.end),
        style: style?.merge(_tomlStyle(token.kind, scheme)),
      ));
      cursor = token.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return TextSpan(children: spans, style: style);
  }

  TextSpan _buildPython(String text, BuildContext context, TextStyle? style) {
    final tokenization = _pythonTokenizer.tokenize(text);
    final scheme = Theme.of(context).colorScheme;
    if (tokenization.tokens.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final token in tokenization.tokens) {
      if (token.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, token.start),
          style: style,
        ));
      }
      spans.add(TextSpan(
        text: text.substring(token.start, token.end),
        style: style?.merge(_pythonStyle(token.kind, scheme)),
      ));
      cursor = token.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return TextSpan(children: spans, style: style);
  }

  /// 结构化文本（json/yaml/ini/sh）的轻量高亮：注释行 + 键。
  TextSpan _buildStructured(
      String text, BuildContext context, TextStyle? style) {
    final scheme = Theme.of(context).colorScheme;
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      // 注释行：# 或 //
      if (trimmed.startsWith('#') || trimmed.startsWith('//')) {
        spans.add(TextSpan(
          text: line,
          style: style?.merge(TextStyle(color: scheme.outline)),
        ));
      } else {
        // 键值分隔：= 或 :
        final sepIndex = _findKeySeparator(line);
        if (sepIndex > 0) {
          spans.add(TextSpan(
            text: line.substring(0, sepIndex),
            style: style?.merge(TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            )),
          ));
          spans.add(TextSpan(text: line.substring(sepIndex), style: style));
        } else {
          spans.add(TextSpan(text: line, style: style));
        }
      }
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return TextSpan(children: spans, style: style);
  }

  int _findKeySeparator(String line) {
    // 在第一个 = 或 : 处分割，但跳过行首空白。
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '=' || c == ':') {
        return i;
      }
      // 遇到引号说明是值，停止。
      if (c == '"' || c == "'") break;
    }
    return -1;
  }

  TextStyle _tomlStyle(TomlTokenKind kind, ColorScheme scheme) {
    switch (kind) {
      case TomlTokenKind.comment:
        return TextStyle(color: scheme.outline);
      case TomlTokenKind.key:
        return TextStyle(color: scheme.primary, fontWeight: FontWeight.w600);
      case TomlTokenKind.table:
        return TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w700);
      case TomlTokenKind.string:
        return TextStyle(color: scheme.secondary);
      case TomlTokenKind.number:
      case TomlTokenKind.boolean:
      case TomlTokenKind.dateTime:
        return TextStyle(color: scheme.error);
      case TomlTokenKind.punctuation:
        return TextStyle(color: scheme.onSurfaceVariant);
      case TomlTokenKind.invalid:
        return TextStyle(
          color: scheme.error,
          decoration: TextDecoration.underline,
          decorationColor: scheme.error,
        );
    }
  }

  TextStyle _pythonStyle(PythonTokenKind kind, ColorScheme scheme) {
    switch (kind) {
      case PythonTokenKind.comment:
        return TextStyle(color: scheme.outline, fontStyle: FontStyle.italic);
      case PythonTokenKind.keyword:
        return TextStyle(color: scheme.primary, fontWeight: FontWeight.w600);
      case PythonTokenKind.builtin:
        return TextStyle(color: scheme.tertiary);
      case PythonTokenKind.string:
        return TextStyle(color: scheme.secondary);
      case PythonTokenKind.number:
        return TextStyle(color: scheme.error);
      case PythonTokenKind.decorator:
        return TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600);
      case PythonTokenKind.operator:
        return TextStyle(color: scheme.onSurfaceVariant);
      case PythonTokenKind.punctuation:
        return TextStyle(color: scheme.onSurfaceVariant);
      case PythonTokenKind.identifier:
        return const TextStyle();
      case PythonTokenKind.whitespace:
        return const TextStyle();
    }
  }

  @override
  void dispose() {
    _lastSource = null;
    super.dispose();
  }
}
