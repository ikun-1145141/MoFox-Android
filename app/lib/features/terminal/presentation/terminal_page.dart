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
  bool _ctrlActive = false;
  bool _altActive = false;
  bool _hasSelection = false;
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
    if (_hasSelection == hasSelection) return;
    setState(() => _hasSelection = hasSelection);
    if (hasSelection && _terminalHapticsEnabled) {
      HapticFeedback.selectionClick();
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
    final selectedText = _selectedTerminalText();
    if (selectedText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: selectedText));
    if (_terminalHapticsEnabled) HapticFeedback.lightImpact();
    _session?.controller.clearSelection();
  }

  String _selectedTerminalText() {
    final session = _session;
    final selection = session?.controller.selection?.normalized;
    if (selection == null || selection.isCollapsed) return '';

    final lines = session!.terminal.buffer.lines;
    final buffer = StringBuffer();
    for (final segment in selection.toSegments()) {
      if (segment.line < 0 || segment.line >= lines.length) continue;

      final line = lines[segment.line];
      final start = (segment.start ?? 0).clamp(0, line.length);
      final end = (segment.end ?? line.length).clamp(start, line.length);
      if (buffer.isNotEmpty && !line.isWrapped) buffer.write('\n');
      buffer.write(_lineText(line, start, end));
    }
    return buffer.toString().trimRight();
  }

  String _lineText(BufferLine line, int start, int end) {
    final buffer = StringBuffer();
    for (var index = start; index < end; index++) {
      final codePoint = line.getCodePoint(index);
      final width = line.getWidth(index);
      if (codePoint == 0) {
        if (width != 0) buffer.write(' ');
        continue;
      }
      buffer.writeCharCode(codePoint);
    }
    return buffer.toString().trimRight();
  }

  void _resizeShell(int cols, int rows, int pixelWidth, int pixelHeight) {
    _session?.resize(cols, rows);
  }

  @override
  void dispose() {
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
                child: TerminalView(
                  session.terminal,
                  controller: session.controller,
                  theme: _mofoxTerminalTheme,
                  autofocus: true,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
            if (_hasSelection)
              _TerminalSelectionBar(
                onCopy: _copySelection,
                onClear: session.controller.clearSelection,
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
}

class _TerminalSelectionBar extends StatelessWidget {
  const _TerminalSelectionBar({
    required this.onCopy,
    required this.onClear,
  });

  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.text_fields, color: scheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '已选中终端文本',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('复制'),
                ),
                IconButton(
                  tooltip: '取消选择',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
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
