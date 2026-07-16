import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../settings/application/app_settings_provider.dart';
import '../application/terminal_session_provider.dart';

/// 终端彩色主题：深色背景 + 标准 16 色 ANSI 调色板。
///
/// xterm 默认主题已经是彩色的，这里显式传一遍确保不受 Flutter 主题影响，
/// 同时把背景色固定为接近终端惯用的深色，避免在浅色 Material 主题下看不清。
const TerminalTheme _mofoxTerminalTheme = TerminalTheme(
  cursor: Color(0xFFAEAFAD),
  selection: Color(0x44AEAFAD),
  foreground: Color(0xFFE0E0E0),
  background: Color(0xFF1A1B26),
  black: Color(0xFF000000),
  red: Color(0xFFCD3131),
  green: Color(0xFF0DBC79),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF11A8CD),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF666666),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF23D18B),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF29B8DB),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({
    super.key,
    this.cwd = '/root',
    this.title = '终端',
  });

  final String cwd;
  final String title;

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  final GlobalKey<TerminalViewState> _terminalViewKey = GlobalKey();
  final GlobalKey _terminalOverlayKey = GlobalKey();

  bool _ctrlActive = false;
  bool _altActive = false;
  bool _hasSelection = false;
  bool _draggingSelectionHandle = false;
  Offset? _draggedHandlePosition;
  OverlayEntry? _selectionToolbarEntry;
  late TerminalSessionSpec _sessionSpec;
  TerminalSession? _session;

  @override
  void initState() {
    super.initState();
    _sessionSpec = TerminalSessionSpec(cwd: widget.cwd, title: widget.title);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachSession(ref.read(terminalSessionProvider(_sessionSpec)));
  }

  @override
  void didUpdateWidget(covariant TerminalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSpec = TerminalSessionSpec(cwd: widget.cwd, title: widget.title);
    if (nextSpec == _sessionSpec) return;
    _detachSession();
    _sessionSpec = nextSpec;
    _attachSession(ref.read(terminalSessionProvider(_sessionSpec)));
  }

  void _attachSession(TerminalSession session) {
    if (identical(_session, session)) return;
    _session = session;
    session.terminal.onOutput = _writeToShell;
    session.terminal.onResize = _resizeShell;
    session.controller.addListener(_handleSelectionChanged);
    _handleSelectionChanged();
  }

  void _detachSession() {
    final session = _session;
    if (session == null) return;
    session.terminal.onOutput = null;
    session.terminal.onResize = null;
    session.controller.removeListener(_handleSelectionChanged);
    _session = null;
  }

  void _handleSelectionChanged() {
    if (!mounted) return;
    final hasSelection = _session?.controller.selection?.isCollapsed == false;
    final selectionStarted = !_hasSelection && hasSelection;
    if (_hasSelection != hasSelection || hasSelection) {
      setState(() => _hasSelection = hasSelection);
    }
    if (selectionStarted && _terminalHapticsEnabled) {
      HapticFeedback.selectionClick();
    }
    if (hasSelection && !_draggingSelectionHandle) {
      _requestSelectionToolbar();
    } else if (!hasSelection) {
      _hideSelectionToolbar();
    }
  }

  bool get _terminalHapticsEnabled =>
      ref.read(appSettingsProvider).valueOrNull?.terminalHapticsEnabled ?? true;

  void _writeToShell(String data) {
    final transformed = _applyPendingModifiers(data);
    if (transformed.isEmpty) return;
    _session?.write(transformed);
  }

  String _applyPendingModifiers(String data) {
    if (!_ctrlActive && !_altActive) return data;

    final buffer = StringBuffer();
    for (final rune in data.runes) {
      var sequence = String.fromCharCode(rune);
      if (_ctrlActive) {
        final upper = sequence.toUpperCase();
        if (upper.codeUnitAt(0) >= 64 && upper.codeUnitAt(0) <= 95) {
          sequence = String.fromCharCode(upper.codeUnitAt(0) & 0x1f);
        }
      }
      if (_altActive) sequence = '\x1b$sequence';
      buffer.write(sequence);
    }

    setState(() {
      _ctrlActive = false;
      _altActive = false;
    });
    return buffer.toString();
  }

  void _sendTerminalSequence(String sequence) {
    _session?.write(sequence);
  }

  void _toggleCtrl() => setState(() => _ctrlActive = !_ctrlActive);

  void _toggleAlt() => setState(() => _altActive = !_altActive);

  void _sendCtrl(String key) {
    final codeUnit = key.toUpperCase().codeUnitAt(0);
    if (codeUnit < 64 || codeUnit > 95) return;
    _sendTerminalSequence(String.fromCharCode(codeUnit & 0x1f));
  }

  Future<void> _copySelection() async {
    final session = _session;
    final selection = session?.controller.selection;
    if (session == null || selection == null || selection.isCollapsed) return;
    final selectedText = session.terminal.buffer.getText(selection);
    if (selectedText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selectedText));
    if (_terminalHapticsEnabled) unawaited(HapticFeedback.lightImpact());
    _hideSelectionToolbar();
    session.controller.clearSelection();
  }

  void _selectAllTerminalText() {
    final session = _session;
    if (session == null) return;
    final terminal = session.terminal;
    _hideSelectionToolbar();
    session.controller.setSelection(
      terminal.buffer.createAnchor(
        0,
        terminal.buffer.height - terminal.viewHeight,
      ),
      terminal.buffer.createAnchor(
        terminal.viewWidth,
        terminal.buffer.height - 1,
      ),
      mode: SelectionMode.line,
    );
  }

  void _requestSelectionToolbar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_draggingSelectionHandle && _hasSelection) {
        _showSelectionToolbar();
      }
    });
  }

  void _showSelectionToolbar() {
    final currentEntry = _selectionToolbarEntry;
    if (currentEntry != null) {
      currentEntry.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(
      builder: _buildSelectionToolbar,
    );
    _selectionToolbarEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Widget _buildSelectionToolbar(BuildContext context) {
    final geometry = _selectionGeometry();
    if (!_hasSelection || _draggingSelectionHandle || geometry == null) {
      return const SizedBox.shrink();
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: geometry.toolbarAnchorAbove,
        secondaryAnchor: geometry.toolbarAnchorBelow,
      ),
      buttonItems: <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          onPressed: _copySelection,
          type: ContextMenuButtonType.copy,
          label: '复制',
        ),
        ContextMenuButtonItem(
          onPressed: _selectAllTerminalText,
          type: ContextMenuButtonType.selectAll,
          label: '全选',
        ),
      ],
    );
  }

  void _hideSelectionToolbar() {
    _removeSelectionToolbarEntry();
  }

  void _removeSelectionToolbarEntry() {
    final entry = _selectionToolbarEntry;
    if (entry == null) return;
    _selectionToolbarEntry = null;
    entry
      ..remove()
      ..dispose();
  }

  _TerminalSelectionGeometry? _selectionGeometry() {
    final selection = _session?.controller.selection?.normalized;
    final terminalView = _terminalViewKey.currentState;
    final overlayBox =
        _terminalOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (selection == null ||
        selection.isCollapsed ||
        terminalView == null ||
        overlayBox == null ||
        !overlayBox.hasSize) {
      return null;
    }

    final renderTerminal = terminalView.renderTerminal;
    final cellHeight = renderTerminal.cellSize.height;
    final startGlobal = renderTerminal.localToGlobal(
      renderTerminal.getOffset(selection.begin),
    );
    final endGlobal = renderTerminal.localToGlobal(
      renderTerminal.getOffset(selection.end),
    );
    final startHandleGlobal = startGlobal.translate(0, cellHeight);
    final endHandleGlobal = endGlobal.translate(0, cellHeight);

    return _TerminalSelectionGeometry(
      startHandleLocal: overlayBox.globalToLocal(startHandleGlobal),
      endHandleLocal: overlayBox.globalToLocal(endHandleGlobal),
      startHandleGlobal: startHandleGlobal,
      endHandleGlobal: endHandleGlobal,
      toolbarAnchorAbove: startGlobal,
      toolbarAnchorBelow: endHandleGlobal,
      lineHeight: cellHeight,
    );
  }

  void _startHandleDrag(bool isStart, DragStartDetails details) {
    final geometry = _selectionGeometry();
    if (geometry == null) return;
    _draggingSelectionHandle = true;
    _draggedHandlePosition =
        isStart ? geometry.startHandleGlobal : geometry.endHandleGlobal;
    _hideSelectionToolbar();
  }

  void _updateHandleDrag(bool isStart, DragUpdateDetails details) {
    final current = _draggedHandlePosition;
    if (current == null) return;
    final next = current + details.delta;
    _draggedHandlePosition = next;
    _updateSelectionEndpoint(isStart: isStart, globalPosition: next);
  }

  void _endHandleDrag(DragEndDetails details) {
    _finishHandleDrag();
  }

  void _cancelHandleDrag() {
    _finishHandleDrag();
  }

  void _finishHandleDrag() {
    _draggingSelectionHandle = false;
    _draggedHandlePosition = null;
    if (_terminalHapticsEnabled) HapticFeedback.selectionClick();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hasSelection) _showSelectionToolbar();
    });
  }

  void _updateSelectionEndpoint({
    required bool isStart,
    required Offset globalPosition,
  }) {
    final session = _session;
    final terminalView = _terminalViewKey.currentState;
    final selection = session?.controller.selection?.normalized;
    if (session == null || terminalView == null || selection == null) return;

    final renderTerminal = terminalView.renderTerminal;
    // Material 手柄的锚点位于字符底边；向上移半行后再映射，避免手柄
    // 刚开始水平拖动就错误跳到下一行。横向按半个字符宽度吸附到最近边界。
    final localPosition = renderTerminal
        .globalToLocal(globalPosition)
        .translate(0, -renderTerminal.cellSize.height / 2);
    final cell = renderTerminal.getCellOffset(localPosition);
    final cellOffset = renderTerminal.getOffset(cell);
    var next = cell;
    if (localPosition.dx >= cellOffset.dx + renderTerminal.cellSize.width / 2) {
      next = CellOffset(cell.x + 1, cell.y);
    }

    final terminal = session.terminal;
    var begin = selection.begin;
    var end = selection.end;
    if (isStart) {
      begin = _compareCellOffsets(next, end) < 0
          ? next
          : _previousCell(end, terminal.viewWidth);
    } else {
      end = _compareCellOffsets(next, begin) > 0
          ? next
          : _nextCell(
              begin,
              terminal.viewWidth,
              terminal.buffer.height,
            );
    }

    session.controller.setSelection(
      terminal.buffer.createAnchorFromOffset(begin),
      terminal.buffer.createAnchorFromOffset(end),
      mode: SelectionMode.line,
    );
  }

  int _compareCellOffsets(CellOffset a, CellOffset b) {
    final rowComparison = a.y.compareTo(b.y);
    return rowComparison != 0 ? rowComparison : a.x.compareTo(b.x);
  }

  CellOffset _previousCell(CellOffset cell, int width) {
    if (cell.x > 0) return CellOffset(cell.x - 1, cell.y);
    if (cell.y > 0) return CellOffset(width - 1, cell.y - 1);
    return cell;
  }

  CellOffset _nextCell(CellOffset cell, int width, int height) {
    if (cell.x < width) return CellOffset(cell.x + 1, cell.y);
    if (cell.y < height - 1) return CellOffset(1, cell.y + 1);
    return cell;
  }

  void _resizeShell(int cols, int rows, int pixelWidth, int pixelHeight) {
    _session?.resize(cols, rows);
  }

  @override
  void dispose() {
    _removeSelectionToolbarEntry();
    _detachSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(terminalSessionProvider(_sessionSpec));
    final error = session.error;
    final terminalHapticsEnabled =
        ref.watch(appSettingsProvider).valueOrNull?.terminalHapticsEnabled ??
            true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: '复制路径',
            onPressed: () => Clipboard.setData(ClipboardData(text: widget.cwd)),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (error != null)
              MaterialBanner(
                content: Text('终端异常：$error'),
                actions: <Widget>[
                  TextButton(
                    onPressed: session.clearError,
                    child: const Text('关闭'),
                  ),
                ],
              ),
            Expanded(
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: _mofoxTerminalTheme.background),
                child: Stack(
                  key: _terminalOverlayKey,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(
                      child: TerminalView(
                        session.terminal,
                        key: _terminalViewKey,
                        controller: session.controller,
                        theme: _mofoxTerminalTheme,
                        autofocus: true,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    if (_hasSelection) ..._buildSelectionHandles(),
                  ],
                ),
              ),
            ),
            _TerminalShortcutBar(
              hapticsEnabled: terminalHapticsEnabled,
              ctrlActive: _ctrlActive,
              altActive: _altActive,
              onCtrl: _toggleCtrl,
              onAlt: _toggleAlt,
              onEsc: () => _sendTerminalSequence('\x1b'),
              onTab: () => _sendTerminalSequence('\t'),
              onEnter: () => _sendTerminalSequence('\r'),
              onArrowUp: () => _sendTerminalSequence('\x1b[A'),
              onArrowDown: () => _sendTerminalSequence('\x1b[B'),
              onArrowRight: () => _sendTerminalSequence('\x1b[C'),
              onArrowLeft: () => _sendTerminalSequence('\x1b[D'),
              onCtrlX: () => _sendCtrl('X'),
              onCtrlO: () => _sendCtrl('O'),
              onCtrlW: () => _sendCtrl('W'),
              onCtrlK: () => _sendCtrl('K'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSelectionHandles() {
    final geometry = _selectionGeometry();
    if (geometry == null) return const <Widget>[];
    return <Widget>[
      _TerminalSelectionHandle(
        position: geometry.startHandleLocal,
        lineHeight: geometry.lineHeight,
        type: TextSelectionHandleType.left,
        onPanStart: (details) => _startHandleDrag(true, details),
        onPanUpdate: (details) => _updateHandleDrag(true, details),
        onPanEnd: _endHandleDrag,
        onPanCancel: _cancelHandleDrag,
      ),
      _TerminalSelectionHandle(
        position: geometry.endHandleLocal,
        lineHeight: geometry.lineHeight,
        type: TextSelectionHandleType.right,
        onPanStart: (details) => _startHandleDrag(false, details),
        onPanUpdate: (details) => _updateHandleDrag(false, details),
        onPanEnd: _endHandleDrag,
        onPanCancel: _cancelHandleDrag,
      ),
    ];
  }
}

class _TerminalSelectionGeometry {
  const _TerminalSelectionGeometry({
    required this.startHandleLocal,
    required this.endHandleLocal,
    required this.startHandleGlobal,
    required this.endHandleGlobal,
    required this.toolbarAnchorAbove,
    required this.toolbarAnchorBelow,
    required this.lineHeight,
  });

  final Offset startHandleLocal;
  final Offset endHandleLocal;
  final Offset startHandleGlobal;
  final Offset endHandleGlobal;
  final Offset toolbarAnchorAbove;
  final Offset toolbarAnchorBelow;
  final double lineHeight;
}

class _TerminalSelectionHandle extends StatelessWidget {
  const _TerminalSelectionHandle({
    required this.position,
    required this.lineHeight,
    required this.type,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  static const double _touchTargetSize = 48;

  final Offset position;
  final double lineHeight;
  final TextSelectionHandleType type;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final GestureDragCancelCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    final handle = materialTextSelectionControls.buildHandle(
      context,
      type,
      lineHeight,
    );
    final handleSize = materialTextSelectionControls.getHandleSize(lineHeight);
    final anchor =
        materialTextSelectionControls.getHandleAnchor(type, lineHeight);
    final visualLeft = _touchTargetSize / 2 - anchor.dx;

    return Positioned(
      left: position.dx - _touchTargetSize / 2,
      top: position.dy,
      width: _touchTargetSize,
      height: _touchTargetSize,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onPanCancel: onPanCancel,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: visualLeft,
              top: -anchor.dy,
              width: handleSize.width,
              height: handleSize.height,
              child: handle,
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalShortcutBar extends StatelessWidget {
  const _TerminalShortcutBar({
    required this.hapticsEnabled,
    required this.ctrlActive,
    required this.altActive,
    required this.onCtrl,
    required this.onAlt,
    required this.onEsc,
    required this.onTab,
    required this.onEnter,
    required this.onArrowUp,
    required this.onArrowDown,
    required this.onArrowRight,
    required this.onArrowLeft,
    required this.onCtrlX,
    required this.onCtrlO,
    required this.onCtrlW,
    required this.onCtrlK,
  });

  final bool hapticsEnabled;
  final bool ctrlActive;
  final bool altActive;
  final VoidCallback onCtrl;
  final VoidCallback onAlt;
  final VoidCallback onEsc;
  final VoidCallback onTab;
  final VoidCallback onEnter;
  final VoidCallback onArrowUp;
  final VoidCallback onArrowDown;
  final VoidCallback onArrowRight;
  final VoidCallback onArrowLeft;
  final VoidCallback onCtrlX;
  final VoidCallback onCtrlO;
  final VoidCallback onCtrlW;
  final VoidCallback onCtrlK;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: <Widget>[
              _TerminalKeyButton(
                label: 'Ctrl',
                selected: ctrlActive,
                hapticsEnabled: hapticsEnabled,
                onPressed: onCtrl,
              ),
              _TerminalKeyButton(
                label: 'Alt',
                selected: altActive,
                hapticsEnabled: hapticsEnabled,
                onPressed: onAlt,
              ),
              _TerminalKeyButton(
                label: 'Esc',
                hapticsEnabled: hapticsEnabled,
                onPressed: onEsc,
              ),
              _TerminalKeyButton(
                label: 'Tab',
                hapticsEnabled: hapticsEnabled,
                onPressed: onTab,
              ),
              _TerminalKeyButton(
                label: '^X',
                hapticsEnabled: hapticsEnabled,
                onPressed: onCtrlX,
              ),
              _TerminalKeyButton(
                label: '^O',
                hapticsEnabled: hapticsEnabled,
                onPressed: onCtrlO,
              ),
              _TerminalKeyButton(
                label: '^W',
                hapticsEnabled: hapticsEnabled,
                onPressed: onCtrlW,
              ),
              _TerminalKeyButton(
                label: '^K',
                hapticsEnabled: hapticsEnabled,
                onPressed: onCtrlK,
              ),
              _TerminalIconKeyButton(
                tooltip: '上',
                icon: Icons.keyboard_arrow_up,
                hapticsEnabled: hapticsEnabled,
                onPressed: onArrowUp,
              ),
              _TerminalIconKeyButton(
                tooltip: '下',
                icon: Icons.keyboard_arrow_down,
                hapticsEnabled: hapticsEnabled,
                onPressed: onArrowDown,
              ),
              _TerminalIconKeyButton(
                tooltip: '左',
                icon: Icons.keyboard_arrow_left,
                hapticsEnabled: hapticsEnabled,
                onPressed: onArrowLeft,
              ),
              _TerminalIconKeyButton(
                tooltip: '右',
                icon: Icons.keyboard_arrow_right,
                hapticsEnabled: hapticsEnabled,
                onPressed: onArrowRight,
              ),
              _TerminalIconKeyButton(
                tooltip: '回车',
                icon: Icons.keyboard_return,
                hapticsEnabled: hapticsEnabled,
                onPressed: onEnter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalKeyButton extends StatelessWidget {
  const _TerminalKeyButton({
    required this.label,
    required this.onPressed,
    required this.hapticsEnabled,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool hapticsEnabled;
  final bool selected;

  void _handlePressed() {
    if (hapticsEnabled) HapticFeedback.selectionClick();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        width: 48,
        height: 36,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            backgroundColor: selected ? scheme.primaryContainer : null,
            foregroundColor: selected ? scheme.onPrimaryContainer : null,
          ),
          onPressed: _handlePressed,
          child: Text(label, maxLines: 1),
        ),
      ),
    );
  }
}

class _TerminalIconKeyButton extends StatelessWidget {
  const _TerminalIconKeyButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.hapticsEnabled,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool hapticsEnabled;

  void _handlePressed() {
    if (hapticsEnabled) HapticFeedback.selectionClick();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox.square(
        dimension: 36,
        child: IconButton.filledTonal(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 22,
          onPressed: _handlePressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
