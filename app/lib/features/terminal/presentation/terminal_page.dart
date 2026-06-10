import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../core/runtime/runtime_bridge.dart';

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
  late final Terminal _terminal;
  StreamSubscription<String>? _outputSubscription;
  String? _sessionId;
  Object? _error;
  bool _ctrlActive = false;
  bool _altActive = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminal.onOutput = _writeToShell;
    _terminal.onResize = _resizeShell;
    unawaited(_openShell());
  }

  Future<void> _openShell() async {
    final runtime = ref.read(runtimeBridgeProvider);
    try {
      _terminal.write('正在打开 ${widget.cwd}\r\n');
      final sessionId = await runtime.openShell(cwd: widget.cwd);
      if (!mounted) {
        await runtime.closeShell(sessionId);
        return;
      }
      _sessionId = sessionId;
      _outputSubscription = runtime.shellOutput(sessionId).listen(
            _terminal.write,
            onError: (Object error, StackTrace stackTrace) {
              if (mounted) setState(() => _error = error);
              _terminal.write('\r\n[终端输出错误] $error\r\n');
            },
          );
      await runtime.resizeShell(
        sessionId,
        _terminal.viewWidth,
        _terminal.viewHeight,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      _terminal.write('\r\n[终端启动失败] $error\r\n');
    }
  }

  void _writeToShell(String data) {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final transformed = _applyPendingModifiers(data);
    if (transformed.isEmpty) return;
    unawaited(ref.read(runtimeBridgeProvider).writeShell(sessionId, transformed));
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
    final sessionId = _sessionId;
    if (sessionId == null) return;
    unawaited(ref.read(runtimeBridgeProvider).writeShell(sessionId, sequence));
  }

  void _toggleCtrl() => setState(() => _ctrlActive = !_ctrlActive);

  void _toggleAlt() => setState(() => _altActive = !_altActive);

  void _sendCtrl(String key) {
    final codeUnit = key.toUpperCase().codeUnitAt(0);
    if (codeUnit < 64 || codeUnit > 95) return;
    _sendTerminalSequence(String.fromCharCode(codeUnit & 0x1f));
  }

  void _resizeShell(int cols, int rows, int pixelWidth, int pixelHeight) {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    unawaited(ref.read(runtimeBridgeProvider).resizeShell(sessionId, cols, rows));
  }

  @override
  void dispose() {
    _terminal.onOutput = null;
    _terminal.onResize = null;
    final sessionId = _sessionId;
    _outputSubscription?.cancel();
    if (sessionId != null) {
      unawaited(ref.read(runtimeBridgeProvider).closeShell(sessionId));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            if (_error != null)
              MaterialBanner(
                content: Text('终端异常：$_error'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(color: scheme.surface),
                child: TerminalView(
                  _terminal,
                  autofocus: true,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
            _TerminalShortcutBar(
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

class _TerminalShortcutBar extends StatelessWidget {
  const _TerminalShortcutBar({
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
                onPressed: onCtrl,
              ),
              _TerminalKeyButton(
                label: 'Alt',
                selected: altActive,
                onPressed: onAlt,
              ),
              _TerminalKeyButton(label: 'Esc', onPressed: onEsc),
              _TerminalKeyButton(label: 'Tab', onPressed: onTab),
              _TerminalKeyButton(label: '^X', onPressed: onCtrlX),
              _TerminalKeyButton(label: '^O', onPressed: onCtrlO),
              _TerminalKeyButton(label: '^W', onPressed: onCtrlW),
              _TerminalKeyButton(label: '^K', onPressed: onCtrlK),
              _TerminalIconKeyButton(
                tooltip: '上',
                icon: Icons.keyboard_arrow_up,
                onPressed: onArrowUp,
              ),
              _TerminalIconKeyButton(
                tooltip: '下',
                icon: Icons.keyboard_arrow_down,
                onPressed: onArrowDown,
              ),
              _TerminalIconKeyButton(
                tooltip: '左',
                icon: Icons.keyboard_arrow_left,
                onPressed: onArrowLeft,
              ),
              _TerminalIconKeyButton(
                tooltip: '右',
                icon: Icons.keyboard_arrow_right,
                onPressed: onArrowRight,
              ),
              _TerminalIconKeyButton(
                tooltip: '回车',
                icon: Icons.keyboard_return,
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
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

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
          onPressed: onPressed,
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

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
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
