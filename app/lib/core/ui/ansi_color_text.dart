import 'package:flutter/material.dart';

/// 解析 ANSI 颜色转义序列并用 [TextSpan] 渲染彩色文本。
///
/// 支持 SGR (Select Graphic Rendition) 序列：
/// - 前景色 30-37 / 90-97 (bright)
/// - 背景色 40-47 / 100-107 (bright)
/// - 重置 0
/// - 粗体 1、暗淡 2、斜体 3、下划线 4、闪烁 5、反色 7
/// - 256 色 `38;5;<n>` / `48;5;<n>`
/// - TrueColor `38;2;r;g;b` / `48;2;r;g;b`
///
/// 不支持的序列被静默忽略，只输出可见字符。
class AnsiColorText extends StatelessWidget {
  const AnsiColorText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final spans = AnsiParser(data, style).parse();
    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

/// ANSI SGR 颜色调色板（标准 16 色 + 256 色扩展）。
class AnsiParser {
  AnsiParser(this.input, this.baseStyle);

  final String input;
  final TextStyle? baseStyle;

  static const List<Color> _standard = <Color>[
    Color(0xFF000000), // 0 black
    Color(0xFFCD3131), // 1 red
    Color(0xFF0DBC79), // 2 green
    Color(0xFFE5C07B), // 3 yellow
    Color(0xFF2472C8), // 4 blue
    Color(0xFFBC3FBC), // 5 magenta
    Color(0xFF11A8CD), // 6 cyan
    Color(0xFFE5E5E5), // 7 white
  ];

  static const List<Color> _bright = <Color>[
    Color(0xFF666666), // 8 brightBlack
    Color(0xFFF14C4C), // 9 brightRed
    Color(0xFF23D18B), // 10 brightGreen
    Color(0xFFF5F543), // 11 brightYellow
    Color(0xFF3B8EEA), // 12 brightBlue
    Color(0xFFD670D6), // 13 brightMagenta
    Color(0xFF29B8DB), // 14 brightCyan
    Color(0xFFFFFFFF), // 15 brightWhite
  ];

  // 256 色调色板索引 16..231：6×6×6 RGB 立方体。
  static final List<Color> _cube = _buildCube();
  // 索引 232..255：灰度渐变。
  static final List<Color> _gray = _buildGrayscale();

  static List<Color> _buildCube() {
    final levels = <int>[0, 95, 135, 175, 215, 255];
    final colors = <Color>[];
    for (var r = 0; r < 6; r++) {
      for (var g = 0; g < 6; g++) {
        for (var b = 0; b < 6; b++) {
          colors.add(Color.fromARGB(
            255,
            levels[r],
            levels[g],
            levels[b],
          ));
        }
      }
    }
    return colors;
  }

  static List<Color> _buildGrayscale() {
    final colors = <Color>[];
    for (var i = 0; i < 24; i++) {
      final v = 8 + i * 10;
      colors.add(Color.fromARGB(255, v, v, v));
    }
    return colors;
  }

  Color _color256(int n) {
    if (n < 8) return _standard[n];
    if (n < 16) return _bright[n - 8];
    if (n < 232) return _cube[n - 16];
    return _gray[n - 232];
  }

  List<InlineSpan> parse() {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var fg = const Color(0xFFE6EDF3);
    var bg = const Color(0x00000000);
    var bold = false;
    var dim = false;
    var italic = false;
    var underline = false;
    // ignore: unused_local_variable
    var blink = false;
    var reverse = false;

    void flush() {
      if (buffer.isEmpty) return;
      Color effectiveFg = fg;
      Color effectiveBg = bg;
      if (reverse) {
        final tmp = effectiveFg;
        effectiveFg = effectiveBg == const Color(0x00000000)
            ? const Color(0xFF1A1B26)
            : effectiveBg;
        effectiveBg = tmp;
      }
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: dim ? effectiveFg.withValues(alpha: 0.5) : effectiveFg,
            backgroundColor: bg == const Color(0x00000000) ? null : bg,
            fontWeight: bold ? FontWeight.bold : null,
            fontStyle: italic ? FontStyle.italic : null,
            decoration: underline ? TextDecoration.underline : null,
          ),
        ),
      );
      buffer.clear();
    }

    var i = 0;
    while (i < input.length) {
      final char = input[i];

      // ESC (0x1B) 或 CSI (0x9B)
      if (char == '\x1B' || char == '\x9B') {
        final next = i + 1;
        if (next < input.length) {
          final nextChar = input[next];
          if (nextChar == '[') {
            // CSI 序列：ESC [ params... final
            var j = next + 1;
            final paramStart = j;
            while (j < input.length) {
              final code = input.codeUnitAt(j);
              if (code >= 0x40 && code <= 0x7E) break;
              j++;
            }
            if (j < input.length) {
              final finalChar = input[j];
              final params = input.substring(paramStart, j);
              if (finalChar == 'm') {
                flush();
                _applySgr(params, (color) => fg = color, (color) => bg = color,
                    () {
                  fg = const Color(0xFFE6EDF3);
                  bg = const Color(0x00000000);
                  bold = false;
                  dim = false;
                  italic = false;
                  underline = false;
                  blink = false;
                  reverse = false;
                },
                    (b) => bold = b,
                    (d) => dim = d,
                    (it) => italic = it,
                    (u) => underline = u,
                    (bl) => blink = bl,
                    (r) => reverse = r);
              }
              i = j + 1;
              continue;
            }
          } else if (nextChar == ']' || nextChar == 'P' || nextChar == '_') {
            // OSC / DCS / APC 序列：跳到 BEL 或 ST (ESC \)
            var j = next + 1;
            while (j < input.length) {
              if (input[j] == '\x07') {
                j++;
                break;
              }
              if (input[j] == '\x1B' &&
                  j + 1 < input.length &&
                  input[j + 1] == '\\') {
                j += 2;
                break;
              }
              j++;
            }
            i = j;
            continue;
          }
        }
      }

      buffer.write(char);
      i++;
    }

    flush();
    return spans;
  }

  void _applySgr(
    String params,
    void Function(Color) setFg,
    void Function(Color) setBg,
    void Function() reset,
    void Function(bool) setBold,
    void Function(bool) setDim,
    void Function(bool) setItalic,
    void Function(bool) setUnderline,
    void Function(bool) setBlink,
    void Function(bool) setReverse,
  ) {
    if (params.isEmpty) {
      reset();
      return;
    }
    final codes = params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
    var i = 0;
    while (i < codes.length) {
      final code = codes[i];
      switch (code) {
        case 0:
          reset();
        case 1:
          setBold(true);
        case 2:
          setDim(true);
        case 3:
          setItalic(true);
        case 4:
          setUnderline(true);
        case 5:
          setBlink(true);
        case 7:
          setReverse(true);
        case 22:
          setBold(false);
          setDim(false);
        case 23:
          setItalic(false);
        case 24:
          setUnderline(false);
        case 25:
          setBlink(false);
        case 27:
          setReverse(false);
        case 38:
          // 前景色扩展
          if (i + 1 < codes.length) {
            final mode = codes[i + 1];
            if (mode == 5 && i + 2 < codes.length) {
              setFg(_color256(codes[i + 2]));
              i += 2;
            } else if (mode == 2 && i + 4 < codes.length) {
              setFg(Color.fromARGB(
                255,
                codes[i + 2].clamp(0, 255),
                codes[i + 3].clamp(0, 255),
                codes[i + 4].clamp(0, 255),
              ));
              i += 4;
            }
          }
        case 39:
          setFg(const Color(0xFFE6EDF3));
        case 48:
          // 背景色扩展
          if (i + 1 < codes.length) {
            final mode = codes[i + 1];
            if (mode == 5 && i + 2 < codes.length) {
              setBg(_color256(codes[i + 2]));
              i += 2;
            } else if (mode == 2 && i + 4 < codes.length) {
              setBg(Color.fromARGB(
                255,
                codes[i + 2].clamp(0, 255),
                codes[i + 3].clamp(0, 255),
                codes[i + 4].clamp(0, 255),
              ));
              i += 4;
            }
          }
        case 49:
          setBg(const Color(0x00000000));
        default:
          if (code >= 30 && code <= 37) {
            setFg(_standard[code - 30]);
          } else if (code >= 40 && code <= 47) {
            setBg(_standard[code - 40]);
          } else if (code >= 90 && code <= 97) {
            setFg(_bright[code - 90]);
          } else if (code >= 100 && code <= 107) {
            setBg(_bright[code - 100]);
          }
      }
      i++;
    }
  }
}
