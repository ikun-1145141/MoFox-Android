import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_bridge.dart';
import '../../instance/domain/instance.dart';

class ProcessConsoleState {
  const ProcessConsoleState({
    required this.status,
    required this.botLogs,
    required this.napcatLogs,
    this.busyAction,
    this.errorMessage,
  });

  factory ProcessConsoleState.initial() => const ProcessConsoleState(
        status: <String, String>{'bot': 'stopped', 'napcat': 'stopped'},
        botLogs: <String>[],
        napcatLogs: <String>[],
      );

  final Map<String, String> status;
  final List<String> botLogs;
  final List<String> napcatLogs;
  final String? busyAction;
  final String? errorMessage;

  bool get isBusy => busyAction != null;
  String get botStatus => status['bot'] ?? 'stopped';
  String get napcatStatus => status['napcat'] ?? 'stopped';

  ProcessConsoleState copyWith({
    Map<String, String>? status,
    List<String>? botLogs,
    List<String>? napcatLogs,
    Object? busyAction = _sentinel,
    Object? errorMessage = _sentinel,
  }) =>
      ProcessConsoleState(
        status: status ?? this.status,
        botLogs: botLogs ?? this.botLogs,
        napcatLogs: napcatLogs ?? this.napcatLogs,
        busyAction: identical(busyAction, _sentinel)
            ? this.busyAction
            : busyAction as String?,
        errorMessage: identical(errorMessage, _sentinel)
            ? this.errorMessage
            : errorMessage as String?,
      );
}

const Object _sentinel = Object();

class ProcessConsoleNotifier extends Notifier<ProcessConsoleState> {
  StreamSubscription<ProcessEvent>? _events;
  Timer? _statusTimer;

  @override
  ProcessConsoleState build() {
    ref.onDispose(() {
      unawaited(_events?.cancel());
      _statusTimer?.cancel();
    });
    final runtime = ref.read(runtimeBridgeProvider);
    _events = runtime.processEvents().listen(_onProcessEvent);
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshStatus()),
    );
    unawaited(refreshStatus());
    return ProcessConsoleState.initial();
  }

  Future<void> startBot(Instance instance) => _runBotAction(
        action: 'start',
        busyLabel: '启动中',
        instance: instance,
        run: (runtime) => runtime.startProcess('bot', args: _botArgs(instance)),
      );

  Future<void> stopBot() => _runBotAction(
        action: 'stop',
        busyLabel: '停止中',
        run: (runtime) => runtime.stopProcess('bot'),
      );

  Future<void> restartBot(Instance instance) => _runBotAction(
        action: 'restart',
        busyLabel: '重启中',
        instance: instance,
        run: (runtime) =>
            runtime.restartProcess('bot', args: _botArgs(instance)),
      );

  Future<void> refreshStatus() async {
    try {
      final status = await ref.read(runtimeBridgeProvider).processStatus();
      state = state.copyWith(status: status, errorMessage: null);
    } catch (error) {
      state = state.copyWith(errorMessage: '刷新进程状态失败：$error');
    }
  }

  Future<void> _runBotAction({
    required String action,
    required String busyLabel,
    required Future<void> Function(RuntimeBridge runtime) run,
    Instance? instance,
  }) async {
    if (state.isBusy) return;
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(busyAction: action, errorMessage: null);
    _appendBotLog(
        '[control] $busyLabel${instance == null ? '' : '：${instance.name}'}');
    try {
      await run(runtime);
      await refreshStatus();
    } catch (error) {
      state = state.copyWith(errorMessage: '$busyLabel失败：$error');
      _appendBotLog('[control] $busyLabel失败：$error');
    } finally {
      state = state.copyWith(busyAction: null);
    }
  }

  void _onProcessEvent(ProcessEvent event) {
    if (event.name == 'bot') {
      _appendBotLog(event.line);
    } else if (event.name == 'napcat') {
      _appendNapcatLog(event.line);
    }
    if (event.line.contains('exited with')) {
      unawaited(refreshStatus());
    }
  }

  void _appendBotLog(String line) {
    state = state.copyWith(botLogs: _tail(<String>[...state.botLogs, line]));
  }

  void _appendNapcatLog(String line) {
    state = state.copyWith(
      napcatLogs: _tail(<String>[...state.napcatLogs, line]),
    );
  }

  Map<String, String> _botArgs(Instance instance) => <String, String>{
        'instanceId': instance.id,
        'repoPath': instance.repoPath,
      };
}

List<String> _tail(List<String> logs) {
  final start = logs.length > _maxLogs ? logs.length - _maxLogs : 0;
  return logs.sublist(start);
}

const int _maxLogs = 400;

final processConsoleProvider =
    NotifierProvider<ProcessConsoleNotifier, ProcessConsoleState>(
  ProcessConsoleNotifier.new,
);
