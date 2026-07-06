import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../../instance/domain/instance.dart';

class ProcessConsoleState {
  const ProcessConsoleState({
    required this.status,
    required this.botLogs,
    required this.napcatLogs,
    this.busyAction,
    this.errorMessage,
    this.napcatQrPayload,
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
  final String? napcatQrPayload;

  bool get isBusy => busyAction != null;
  String get botStatus => status['bot'] ?? 'stopped';
  String get napcatStatus => status['napcat'] ?? 'stopped';

  ProcessConsoleState copyWith({
    Map<String, String>? status,
    List<String>? botLogs,
    List<String>? napcatLogs,
    Object? busyAction = _sentinel,
    Object? errorMessage = _sentinel,
    Object? napcatQrPayload = _sentinel,
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
        napcatQrPayload: identical(napcatQrPayload, _sentinel)
            ? this.napcatQrPayload
            : napcatQrPayload as String?,
      );
}

const Object _sentinel = Object();

class ProcessConsoleNotifier extends Notifier<ProcessConsoleState> {
  StreamSubscription<ProcessEvent>? _events;
  Timer? _statusTimer;
  /// 同步忙标志：防止快速点击在 Riverpod 状态传播前绕过 isBusy 守卫。
  bool _actionInProgress = false;

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

  Future<void> startNapcat(Instance instance) {
    appLogger.i(
        'process: startNapcat instance=${instance.id} botQq=${instance.botQq}');
    return _runNapcatAction(
      action: 'start-napcat',
      busyLabel: 'NapCat 登录并启动中',
      run: (runtime) async {
        final args = _napcatArgs(instance);
        final streamedLogs = <String>[];
        final loginEvents = runtime.installEvents().listen((event) {
          if (event.task != 'napcatLogin') return;
          streamedLogs.add(event.line);
          if (event.line.startsWith('MOFOX_QR_PAYLOAD=')) {
            final separator = event.line.indexOf('=');
            final payload = event.line.substring(separator + 1);
            appLogger.i(
                'process: napcat QR payload received (len=${payload.length})');
            state = state.copyWith(
              napcatQrPayload: payload,
            );
            return;
          }
          if (event.line.contains('[napcat] 登录成功')) {
            appLogger.i('process: napcat login success');
            state = state.copyWith(napcatQrPayload: null);
          }
          _appendNapcatLog(event.line);
        });
        late final RuntimeTaskResult loginResult;
        try {
          loginResult = await runtime.runInstallTask('napcatLogin', args: args);
        } finally {
          await loginEvents.cancel();
        }
        if (!loginResult.success) {
          appLogger.e('process: napcat login failed: ${loginResult.error}');
          if (streamedLogs.isEmpty) {
            for (final line in loginResult.logs) {
              _appendNapcatLog(line);
            }
          }
          throw loginResult.error ?? 'NapCat 扫码登录失败';
        }
        if (streamedLogs.isEmpty) {
          for (final line in loginResult.logs) {
            _appendNapcatLog(line);
          }
        }
        _appendNapcatLog('[control] NapCat 扫码登录完成');
        state = state.copyWith(napcatQrPayload: null);
        appLogger.i('process: starting napcat process');
        await runtime.startProcess('napcat', args: args);
      },
    );
  }

  Future<void> stopNapcat() => _runNapcatAction(
        action: 'stop-napcat',
        busyLabel: 'NapCat 停止中',
        run: (runtime) => runtime.stopProcess('napcat'),
      );

  Future<void> restartNapcat(Instance instance) => _runNapcatAction(
        action: 'restart-napcat',
        busyLabel: 'NapCat 重启中',
        run: (runtime) => runtime.restartProcess(
          'napcat',
          args: _napcatArgs(instance),
        ),
      );

  Future<void> refreshStatus() async {
    try {
      final status = await ref.read(runtimeBridgeProvider).processStatus();
      state = state.copyWith(status: status, errorMessage: null);
    } catch (error) {
      appLogger.w('process: refreshStatus failed: $error');
      state = state.copyWith(errorMessage: '刷新进程状态失败：$error');
    }
  }

  Future<void> _runBotAction({
    required String action,
    required String busyLabel,
    required Future<void> Function(RuntimeBridge runtime) run,
    Instance? instance,
  }) async {
    // 同步守卫：快速点击时 state.isBusy 还没传播，用本地标志挡住。
    if (_actionInProgress || state.isBusy) return;
    _actionInProgress = true;
    appLogger.i(
        'process: bot $action${instance == null ? '' : ' instance=${instance.id}'}');
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(busyAction: action, errorMessage: null);
    _appendBotLog(
        '[control] $busyLabel${instance == null ? '' : '：${instance.name}'}');
    try {
      await run(runtime);
      await refreshStatus();
    } catch (error) {
      appLogger.e('process: bot $action failed', error: error);
      state = state.copyWith(errorMessage: '$busyLabel失败：$error');
      _appendBotLog('[control] $busyLabel失败：$error');
    } finally {
      state = state.copyWith(busyAction: null);
      _actionInProgress = false;
    }
  }

  Future<void> _runNapcatAction({
    required String action,
    required String busyLabel,
    required Future<void> Function(RuntimeBridge runtime) run,
  }) async {
    if (_actionInProgress || state.isBusy) return;
    _actionInProgress = true;
    appLogger.i('process: napcat $action');
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(
      busyAction: action,
      errorMessage: null,
      napcatQrPayload: null,
    );
    _appendNapcatLog('[control] $busyLabel');
    try {
      await run(runtime);
      await refreshStatus();
    } catch (error) {
      appLogger.e('process: napcat $action failed', error: error);
      state = state.copyWith(
        errorMessage: '$busyLabel失败：$error',
        napcatQrPayload: null,
      );
      _appendNapcatLog('[control] $busyLabel失败：$error');
    } finally {
      state = state.copyWith(busyAction: null);
      _actionInProgress = false;
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

  Map<String, String> _napcatArgs(Instance instance) => <String, String>{
        'botQq': instance.botQq,
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
