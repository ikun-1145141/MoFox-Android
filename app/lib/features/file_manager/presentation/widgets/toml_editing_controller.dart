import 'package:flutter/material.dart';

import '../../application/toml_tokenizer.dart';

/// TOML 语法高亮编辑控制器。
///
/// 通过覆写 [buildTextSpan] 输出带颜色的 token span。每次文本变更时重新
/// tokenize（首版不做增量缓存，依赖 tokenizer 足够快；后续可按行缓存优化）。
/// 保留 selection、composing range 和 IME 行为，不引入 WebView。
class TomlEditingController extends TextEditingController {
  TomlEditingController({super.text});

  static const TomlTokenizer _tokenizer = TomlTokenizer();

  TomlTokenization? _lastTokenization;
  String? _lastSource;

  /// 最近一次 tokenize 结果，供行号/诊断定位等外部使用。
  TomlTokenization? get lastTokenization => _lastTokenization;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    // 文本未变化时复用上次结果。
    if (_lastSource != text) {
      _lastSource = text;
      _lastTokenization = _tokenizer.tokenize(text);
    }
    final tokenization = _lastTokenization;
    if (tokenization == null || tokenization.tokens.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final scheme = Theme.of(context).colorScheme;
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
        style: style?.merge(_styleFor(token.kind, scheme)),
      ));
      cursor = token.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return TextSpan(children: spans, style: style);
  }

  TextStyle _styleFor(TomlTokenKind kind, ColorScheme scheme) {
    switch (kind) {
      case TomlTokenKind.comment:
        return TextStyle(color: scheme.outline);
      case TomlTokenKind.key:
        return TextStyle(color: scheme.primary, fontWeight: FontWeight.w600);
      case TomlTokenKind.table:
        return TextStyle(
          color: scheme.tertiary,
          fontWeight: FontWeight.w700,
        );
      case TomlTokenKind.string:
        return TextStyle(color: scheme.secondary);
      case TomlTokenKind.number:
        return TextStyle(color: scheme.error);
      case TomlTokenKind.boolean:
        return TextStyle(color: scheme.error);
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

  @override
  void dispose() {
    _lastTokenization = null;
    _lastSource = null;
    super.dispose();
  }
}
