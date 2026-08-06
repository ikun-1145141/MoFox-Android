import 'package:flutter/material.dart';

/// 轻量 Markdown 渲染器。
///
/// 不依赖第三方包，覆盖常用语法：标题、段落、有序/无序列表、代码块、引用、
/// 分隔线、行内格式（粗体、斜体、行内代码、链接）。不做 GFM 表格、脚注等
/// 高级特性，避免解析复杂度失控。
///
/// 解析与渲染分离：[parseMarkdown] 返回 [MarkdownDocument]，可在测试中独立
/// 断言；[MarkdownView] 负责把文档渲染为 Flutter Widget。
class MarkdownDocument {
  const MarkdownDocument({required this.blocks});

  final List<MarkdownBlock> blocks;
}

/// Markdown 块级元素。
abstract class MarkdownBlock {
  const MarkdownBlock();
}

class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading({required this.level, required this.inline});
  final int level; // 1..6
  final List<MarkdownInline> inline;
}

class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph({required this.inline});
  final List<MarkdownInline> inline;
}

class MarkdownListItem extends MarkdownBlock {
  const MarkdownListItem(
      {required this.ordered, required this.index, required this.inline});
  final bool ordered;
  final int index; // 有序列表的序号（从 1 起）
  final List<MarkdownInline> inline;
}

class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock({required this.language, required this.code});
  final String? language;
  final String code;
}

class MarkdownBlockquote extends MarkdownBlock {
  const MarkdownBlockquote({required this.inline});
  final List<MarkdownInline> inline;
}

class MarkdownThematicBreak extends MarkdownBlock {
  const MarkdownThematicBreak();
}

/// Markdown 行内元素。
abstract class MarkdownInline {
  const MarkdownInline();
}

class MarkdownText extends MarkdownInline {
  const MarkdownText(this.text);
  final String text;
}

class MarkdownBold extends MarkdownInline {
  const MarkdownBold(this.inline);
  final List<MarkdownInline> inline;
}

class MarkdownItalic extends MarkdownInline {
  const MarkdownItalic(this.inline);
  final List<MarkdownInline> inline;
}

class MarkdownInlineCode extends MarkdownInline {
  const MarkdownInlineCode(this.code);
  final String code;
}

class MarkdownLink extends MarkdownInline {
  const MarkdownLink({required this.inline, required this.url});
  final List<MarkdownInline> inline;
  final String url;
}

/// 解析 markdown 源码为块级文档。
MarkdownDocument parseMarkdown(String source) {
  final lines = source.split('\n');
  final blocks = <MarkdownBlock>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // 跳过空行
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // 围栏代码块 ```
    final fenceMatch = _fencedCodeRegExp.firstMatch(line);
    if (fenceMatch != null) {
      final language = fenceMatch.group(1);
      final code = <String>[];
      i++;
      while (i < lines.length && !line.startsWith(lines[i].trimLeft())) {
        if (lines[i].trimLeft().startsWith('```')) break;
        code.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // 跳过闭合 ```
      blocks.add(MarkdownCodeBlock(
        language: language?.isEmpty == true ? null : language,
        code: code.join('\n'),
      ));
      continue;
    }

    // 分隔线
    if (_thematicBreakRegExp.hasMatch(line.trim())) {
      blocks.add(const MarkdownThematicBreak());
      i++;
      continue;
    }

    // 标题
    final headingMatch = _headingRegExp.firstMatch(line);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final text = headingMatch.group(2)!.trim();
      blocks.add(MarkdownHeading(
        level: level,
        inline: parseInline(text),
      ));
      i++;
      continue;
    }

    // 引用 >
    final quoteMatch = _blockquoteRegExp.firstMatch(line);
    if (quoteMatch != null) {
      final buffer = <String>[];
      while (i < lines.length) {
        final m = _blockquoteRegExp.firstMatch(lines[i]);
        if (m == null) break;
        buffer.add(m.group(1)!);
        i++;
      }
      blocks.add(MarkdownBlockquote(inline: parseInline(buffer.join(' '))));
      continue;
    }

    // 无序列表
    if (_unorderedListRegExp.hasMatch(line)) {
      var index = 0;
      while (i < lines.length && _unorderedListRegExp.hasMatch(lines[i])) {
        final text = _unorderedListRegExp.firstMatch(lines[i])!.group(1)!;
        blocks.add(MarkdownListItem(
          ordered: false,
          index: ++index,
          inline: parseInline(text.trim()),
        ));
        i++;
      }
      continue;
    }

    // 有序列表
    final orderedMatch = _orderedListRegExp.firstMatch(line);
    if (orderedMatch != null) {
      while (i < lines.length) {
        final m = _orderedListRegExp.firstMatch(lines[i]);
        if (m == null) break;
        final num = int.tryParse(m.group(1)!) ?? 1;
        blocks.add(MarkdownListItem(
          ordered: true,
          index: num,
          inline: parseInline(m.group(2)!.trim()),
        ));
        i++;
      }
      continue;
    }

    // 段落：连续非空行合并
    final buffer = <String>[line];
    i++;
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !_isBlockStart(lines[i])) {
      buffer.add(lines[i]);
      i++;
    }
    blocks.add(MarkdownParagraph(inline: parseInline(buffer.join(' '))));
  }
  return MarkdownDocument(blocks: blocks);
}

bool _isBlockStart(String line) {
  if (_headingRegExp.hasMatch(line)) return true;
  if (_thematicBreakRegExp.hasMatch(line.trim())) return true;
  if (_fencedCodeRegExp.hasMatch(line)) return true;
  if (_blockquoteRegExp.hasMatch(line)) return true;
  if (_unorderedListRegExp.hasMatch(line)) return true;
  if (_orderedListRegExp.hasMatch(line)) return true;
  return false;
}

/// 解析行内格式：**bold** *italic* `code` [text](url)
List<MarkdownInline> parseInline(String text) {
  final result = <MarkdownInline>[];
  var buffer = StringBuffer();
  var i = 0;

  void flushBuffer() {
    if (buffer.isNotEmpty) {
      result.add(MarkdownText(buffer.toString()));
      buffer = StringBuffer();
    }
  }

  while (i < text.length) {
    // 行内代码 `code`
    if (text[i] == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i) {
        flushBuffer();
        result.add(MarkdownInlineCode(text.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }
    // 链接 [text](url)
    if (text[i] == '[') {
      final closeBracket = text.indexOf(']', i + 1);
      if (closeBracket > i &&
          closeBracket + 1 < text.length &&
          text[closeBracket + 1] == '(') {
        final closeParen = text.indexOf(')', closeBracket + 2);
        if (closeParen > closeBracket) {
          flushBuffer();
          final linkText = text.substring(i + 1, closeBracket);
          final url = text.substring(closeBracket + 2, closeParen);
          result.add(MarkdownLink(
            inline: parseInline(linkText),
            url: url,
          ));
          i = closeParen + 1;
          continue;
        }
      }
    }
    // 粗体 **text**
    if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
      final end = text.indexOf('**', i + 2);
      if (end > i + 1) {
        flushBuffer();
        result.add(MarkdownBold(parseInline(text.substring(i + 2, end))));
        i = end + 2;
        continue;
      }
    }
    // 斜体 *text*
    if (text[i] == '*') {
      final end = text.indexOf('*', i + 1);
      if (end > i) {
        flushBuffer();
        result.add(MarkdownItalic(parseInline(text.substring(i + 1, end))));
        i = end + 1;
        continue;
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flushBuffer();
  return result;
}

final RegExp _headingRegExp = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _thematicBreakRegExp = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
final RegExp _fencedCodeRegExp = RegExp(r'^```\s*(\w*)\s*$');
final RegExp _blockquoteRegExp = RegExp(r'^>\s?(.*)$');
final RegExp _unorderedListRegExp = RegExp(r'^[-*+]\s+(.*)$');
final RegExp _orderedListRegExp = RegExp(r'^(\d+)\.\s+(.*)$');

/// 把 [MarkdownInline] 列表渲染为 [TextSpan]。
TextSpan buildInlineSpans(
  List<MarkdownInline> inline,
  TextStyle base,
  ColorScheme scheme,
) {
  final children = <InlineSpan>[];
  for (final node in inline) {
    children.add(_inlineToSpan(node, base, scheme));
  }
  return TextSpan(children: children, style: base);
}

InlineSpan _inlineToSpan(
  MarkdownInline node,
  TextStyle base,
  ColorScheme scheme,
) {
  if (node is MarkdownText) {
    return TextSpan(text: node.text, style: base);
  }
  if (node is MarkdownBold) {
    return TextSpan(
      children: node.inline.map((n) => _inlineToSpan(n, base, scheme)).toList(),
      style: base.copyWith(fontWeight: FontWeight.bold),
    );
  }
  if (node is MarkdownItalic) {
    return TextSpan(
      children: node.inline.map((n) => _inlineToSpan(n, base, scheme)).toList(),
      style: base.copyWith(fontStyle: FontStyle.italic),
    );
  }
  if (node is MarkdownInlineCode) {
    return TextSpan(
      text: node.code,
      style: base.copyWith(
        fontFamily: 'monospace',
        color: scheme.secondary,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
  if (node is MarkdownLink) {
    return TextSpan(
      children: node.inline.map((n) => _inlineToSpan(n, base, scheme)).toList(),
      style: base.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
    );
  }
  return TextSpan(text: '', style: base);
}

/// Markdown 只读渲染视图。
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    required this.document,
    required this.onLinkTap,
    super.key,
  });

  final MarkdownDocument document;
  final void Function(String url) onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final block in document.blocks)
            _buildBlock(block, context, scheme, text),
        ],
      ),
    );
  }

  Widget _buildBlock(
    MarkdownBlock block,
    BuildContext context,
    ColorScheme scheme,
    TextTheme text,
  ) {
    final base = text.bodyMedium!;
    switch (block) {
      case MarkdownHeading(:final level, :final inline):
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: RichText(
            text: buildInlineSpans(
              inline,
              base.copyWith(
                fontSize: _headingSize(level, base.fontSize ?? 14),
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
              scheme,
            ),
          ),
        );
      case MarkdownParagraph(:final inline):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: RichText(
            text: buildInlineSpans(inline, base.copyWith(height: 1.6), scheme),
          ),
        );
      case MarkdownListItem(:final ordered, :final index, :final inline):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ordered ? 28 : 20,
                child: Text(
                  ordered ? '$index.' : '•',
                  style: base.copyWith(height: 1.6),
                ),
              ),
              Expanded(
                child: RichText(
                  text: buildInlineSpans(
                    inline,
                    base.copyWith(height: 1.6),
                    scheme,
                  ),
                ),
              ),
            ],
          ),
        );
      case MarkdownCodeBlock(:final language, :final code):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (language != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      language,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                SelectableText(
                  code,
                  style: base.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['RobotoMono', 'Courier New'],
                    fontSize: base.fontSize! * 0.9,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      case MarkdownBlockquote(:final inline):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: scheme.outline, width: 3),
              ),
              color: scheme.surfaceContainerLow,
            ),
            child: RichText(
              text: buildInlineSpans(
                inline,
                base.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
                scheme,
              ),
            ),
          ),
        );
      case MarkdownThematicBreak():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: scheme.outline),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  double _headingSize(int level, double base) {
    switch (level) {
      case 1:
        return base * 1.8;
      case 2:
        return base * 1.5;
      case 3:
        return base * 1.3;
      case 4:
        return base * 1.15;
      default:
        return base;
    }
  }
}
