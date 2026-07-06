import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../core/runtime/runtime_bridge.dart';

class TerminalSessionSpec {
  const TerminalSessionSpec({required this.cwd, required this.title});

  final String cwd;
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalSessionSpec &&
          runtimeType == other.runtimeType &&
          cwd == other.cwd &&
          title == other.title;

  @override
  int get hashCode => Object.hash(cwd, title);
}

class TerminalSession extends ChangeNotifier {
  TerminalSession({required RuntimeBridge runtime, required this.spec})
      : _runtime = runtime,
        terminal = Terminal(maxLines: 10000),
        controller = TerminalController() {
    unawaited(_openShell());
  }

  final RuntimeBridge _runtime;
  final TerminalSessionSpec spec;
  final Terminal terminal;
  final TerminalController controller;

  StreamSubscription<String>? _outputSubscription;
  String? _sessionId;
  Object? _error;
  bool _disposed = false;

  Object? get error => _error;

  Future<void> _openShell() async {
    try {
      terminal.write('正在打开 ${spec.cwd}\r\n');
      final sessionId = await _runtime.openShell(cwd: spec.cwd);
      if (_disposed) {
        await _runtime.closeShell(sessionId);
        return;
      }
      _sessionId = sessionId;
      _outputSubscription = _runtime.shellOutput(sessionId).listen(
        terminal.write,
        onError: (Object error, StackTrace stackTrace) {
          _error = error;
          terminal.write('\r\n[终端输出错误] $error\r\n');
          notifyListeners();
        },
      );
      await _runtime.resizeShell(
        sessionId,
        terminal.viewWidth,
        terminal.viewHeight,
      );
    } catch (error) {
      if (_disposed) return;
      _error = error;
      terminal.write('\r\n[终端启动失败] $error\r\n');
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void write(String data) {
    final sessionId = _sessionId;
    if (sessionId == null || data.isEmpty) return;
    unawaited(_runtime.writeShell(sessionId, data));
  }

  void resize(int cols, int rows) {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    unawaited(_runtime.resizeShell(sessionId, cols, rows));
  }

  @override
  void dispose() {
    _disposed = true;
    terminal.onOutput = null;
    terminal.onResize = null;
    controller.dispose();
    unawaited(_outputSubscription?.cancel());
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(_runtime.closeShell(sessionId));
    }
    super.dispose();
  }
}

final terminalSessionProvider =
    ChangeNotifierProvider.family<TerminalSession, TerminalSessionSpec>(
  (ref, spec) => TerminalSession(
    runtime: ref.read(runtimeBridgeProvider),
    spec: spec,
  ),
);
