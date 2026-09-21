import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 与文本编辑器共用滚动位置的行号栏。
///
/// 只绘制当前视口可见的行号，避免为大文件创建成千上万个
/// [Text] widget。[textStyle] 必须与编辑区使用相同的字号和行高，
/// 以保证长文件不会逐行漂移。
class LineNumberGutter extends StatefulWidget {
  const LineNumberGutter({
    required this.controller,
    required this.scrollController,
    required this.textStyle,
    this.topPadding = 8,
    super.key,
  });

  final TextEditingController controller;
  final ScrollController scrollController;
  final TextStyle textStyle;
  final double topPadding;

  @override
  State<LineNumberGutter> createState() => _LineNumberGutterState();
}

class _LineNumberGutterState extends State<LineNumberGutter> {
  @override
  void initState() {
    super.initState();
    _addListeners();
  }

  @override
  void didUpdateWidget(covariant LineNumberGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.scrollController != widget.scrollController) {
      oldWidget.controller.removeListener(_handleChange);
      oldWidget.scrollController.removeListener(_handleChange);
      _addListeners();
    }
  }

  void _addListeners() {
    widget.controller.addListener(_handleChange);
    widget.scrollController.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    widget.scrollController.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
    final digits = math.max(2, lineCount.toString().length);
    final width = math.max(48.0, 24 + digits * 8.0);
    final pixels = widget.scrollController.hasClients
        ? widget.scrollController.position.pixels
        : 0.0;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: ClipRect(
          child: CustomPaint(
            painter: _LineNumberPainter(
              lineCount: lineCount,
              scrollOffset: pixels,
              topPadding: widget.topPadding,
              editorStyle: widget.textStyle,
              color: scheme.outline,
              textDirection: Directionality.of(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineNumberPainter extends CustomPainter {
  const _LineNumberPainter({
    required this.lineCount,
    required this.scrollOffset,
    required this.topPadding,
    required this.editorStyle,
    required this.color,
    required this.textDirection,
  });

  final int lineCount;
  final double scrollOffset;
  final double topPadding;
  final TextStyle editorStyle;
  final Color color;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final metricsPainter = TextPainter(
      text: TextSpan(text: '0', style: editorStyle),
      textDirection: textDirection,
    )..layout();
    final lineHeight = metricsPainter.preferredLineHeight;
    if (lineHeight <= 0) return;

    final firstIndex = math.max(
      0,
      ((scrollOffset - topPadding) / lineHeight).floor(),
    );
    final visibleCount = (size.height / lineHeight).ceil() + 2;
    final lastIndex = math.min(lineCount - 1, firstIndex + visibleCount);
    final numberStyle = editorStyle.copyWith(
      color: color,
      fontSize: (editorStyle.fontSize ?? 14) * 0.82,
      height: 1,
    );

    for (var index = firstIndex; index <= lastIndex; index++) {
      final painter = TextPainter(
        text: TextSpan(text: '${index + 1}', style: numberStyle),
        textDirection: textDirection,
        textAlign: TextAlign.right,
      )..layout(maxWidth: size.width - 12);
      final y = topPadding + index * lineHeight - scrollOffset;
      painter.paint(
        canvas,
        Offset(
          size.width - painter.width - 8,
          y + (lineHeight - painter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineNumberPainter oldDelegate) =>
      lineCount != oldDelegate.lineCount ||
      scrollOffset != oldDelegate.scrollOffset ||
      topPadding != oldDelegate.topPadding ||
      editorStyle != oldDelegate.editorStyle ||
      color != oldDelegate.color ||
      textDirection != oldDelegate.textDirection;
}
