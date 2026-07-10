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
    this.napcatWebuiUrl,
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

  /// NapCat WebUI 地址（含 token），从 napcat 日志解析。
  /// 形如 `http://127.0.0.1:6099/webui?token=xxx`。
  final String? napcatWebuiUrl;

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
    Object? napcatWebuiUrl = _sentinel,
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
        napcatWebuiUrl: identical(napcatWebuiUrl, _sentinel)
            ? this.napcatWebuiUrl
            : napcatWebuiUrl as String?,
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
      busyLabel: 'NapCat 启动中',
      run: (runtime) async {
        final args = _napcatArgs(instance);
        appLogger.i('process: starting napcat process directly');
        await runtime.startProcess('napcat', args: args);
        // 给 napcat 进程 2 秒稳定时间，避免 refreshStatus 读到刚启动还未就绪的状态
        await Future<void>.delayed(const Duration(seconds: 2));
      },
    );
  }

  Future<void> stopNapcat() => _runNapcatAction(
        action: 'stop-napcat',
        busyLabel: 'NapCat 停止中',
        run: (runtime) => runtime.stopProcess('napcat'),
      );

  /// 取消正在进行的 NapCat 扫码登录。
  /// 新流程中 NapCat 进程直接启动，取消登录 = 停止 napcat 进程。
  /// 不在这里清 napcatQrPayload——由调用方在 pop sheet 后清，
  /// 避免此处 setState 触发 listener 在 sheet 关闭动画中二次 pop 导致崩溃。
  Future<void> cancelNapcatLogin() async {
    appLogger.i('process: cancelNapcatLogin (stop napcat process)');
    final runtime = ref.read(runtimeBridgeProvider);
    try {
      await runtime.stopProcess('napcat');
    } catch (error) {
      appLogger.e('process: cancelNapcatLogin failed', error: error);
    }
  }

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
      // 检测 QR 码标记行：进程脚本后台监控 QR 文件并输出 MOFOX_QR_IMAGE=<path>
      if (event.line.startsWith('MOFOX_QR_IMAGE=')) {
        final hostPath = event.line.substring('MOFOX_QR_IMAGE='.length);
        final payload = 'file:$hostPath';
        appLogger.i(
            'process: napcat QR from process stream (len=${payload.length})');
        state = state.copyWith(napcatQrPayload: payload);
        return;
      }
      // 登录成功标记
      if (event.line.contains('配置加载')) {
        appLogger.i('process: napcat login success detected');
        state = state.copyWith(napcatQrPayload: null);
      }
      // 解析 NapCat WebUI 地址（含 token）
      // 形如：[WebUi] WebUi User Panel Url: http://127.0.0.1:6099/webui?token=xxx
      final webuiMatch = RegExp(
        r'WebUi User Panel Url:\s*(https?://[^\s]+)',
      ).firstMatch(event.line);
      if (webuiMatch != null) {
        final url = webuiMatch.group(1)!;
        appLogger.i('process: napcat webui url detected: $url');
        state = state.copyWith(napcatWebuiUrl: url);
      }
      _appendNapcatLog(event.line);
    }
    if (event.line.contains('exited with')) {
      // 进程退出时清理对应的 WebUI 地址
      if (event.name == 'napcat') {
        state = state.copyWith(napcatWebuiUrl: null);
      }
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
