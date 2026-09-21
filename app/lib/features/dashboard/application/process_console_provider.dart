import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/platform/screen_wake_lock.dart';
import 'package:mofox_android/core/runtime/runtime_bridge.dart';
import 'package:mofox_android/core/utils/app_logger.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

class ProcessConsoleState {
  const ProcessConsoleState({
    required this.status,
    required this.botLogs,
    required this.napcatLogs,
    this.activeInstanceId,
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

  /// 当前占用原生单实例进程槽位的实例。
  ///
  /// Bot 与 NapCat 的原生托管器都是全局唯一的，因此裸的 [botStatus] / [napcatStatus]
  /// 不能直接用于任意实例卡片。界面应通过 [botStatusFor] / [napcatStatusFor]
  /// 读取实例作用域内的状态。
  final String? activeInstanceId;
  final String? busyAction;
  final String? errorMessage;
  final String? napcatQrPayload;

  /// NapCat WebUI 地址（含 token），从 napcat 日志解析。
  /// 形如 `http://127.0.0.1:6099/webui?token=xxx`。
  final String? napcatWebuiUrl;

  bool get isBusy => busyAction != null;
  String get botStatus => status['bot'] ?? 'stopped';
  String get napcatStatus => status['napcat'] ?? 'stopped';

  bool get hasRunningProcess =>
      botStatus == 'running' || napcatStatus == 'running';

  bool isActiveInstance(String instanceId) =>
      activeInstanceId != null && activeInstanceId == instanceId;

  String botStatusFor(String instanceId) =>
      isActiveInstance(instanceId) ? botStatus : 'stopped';

  String napcatStatusFor(String instanceId) =>
      isActiveInstance(instanceId) ? napcatStatus : 'stopped';

  ProcessConsoleState copyWith({
    Map<String, String>? status,
    List<String>? botLogs,
    List<String>? napcatLogs,
    Object? activeInstanceId = _sentinel,
    Object? busyAction = _sentinel,
    Object? errorMessage = _sentinel,
    Object? napcatQrPayload = _sentinel,
    Object? napcatWebuiUrl = _sentinel,
  }) =>
      ProcessConsoleState(
        status: status ?? this.status,
        botLogs: botLogs ?? this.botLogs,
        napcatLogs: napcatLogs ?? this.napcatLogs,
        activeInstanceId: identical(activeInstanceId, _sentinel)
            ? this.activeInstanceId
            : activeInstanceId as String?,
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

  Future<void> startBot(Instance instance) {
    if (!_canActivate(instance.id)) return Future<void>.value();
    return _runBotAction(
      action: 'start',
      busyLabel: '启动中',
      instance: instance,
      run: (runtime) => runtime.startProcess('bot', args: _botArgs(instance)),
    );
  }

  Future<void> stopBot() => _runBotAction(
        action: 'stop',
        busyLabel: '停止中',
        run: (runtime) => runtime.stopProcess('bot'),
      );

  Future<void> restartBot(Instance instance) {
    if (!_canActivate(instance.id)) return Future<void>.value();
    return _runBotAction(
      action: 'restart',
      busyLabel: '重启中',
      instance: instance,
      run: (runtime) => runtime.restartProcess('bot', args: _botArgs(instance)),
    );
  }

  Future<void> startNapcat(Instance instance) {
    if (!_canActivate(instance.id)) return Future<void>.value();
    appLogger.i(
      'process: startNapcat instance=${instance.id}',
    );
    return ref.read(screenWakeLockProvider).keepAwakeWhile(
          () => _runNapcatAction(
            action: 'start-napcat',
            busyLabel: 'NapCat 启动中',
            instance: instance,
            run: (runtime) async {
              await _ensureNapcatReady(runtime);
              final args = _napcatArgs(instance);
              appLogger.i('process: starting napcat process');
              await runtime.startProcess('napcat', args: args);
              // 给 napcat 进程 2 秒稳定时间，避免 refreshStatus 读到刚启动还未就绪的状态
              await Future<void>.delayed(const Duration(seconds: 2));
            },
          ),
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
      final status = <String, String>{
        ...state.status,
        'napcat': 'stopped',
      };
      state = state.copyWith(
        status: status,
        activeInstanceId:
            status['bot'] == 'running' ? state.activeInstanceId : null,
      );
      await refreshStatus();
    } catch (error) {
      appLogger.e('process: cancelNapcatLogin failed', error: error);
    }
  }

  Future<void> restartNapcat(Instance instance) {
    if (!_canActivate(instance.id)) return Future<void>.value();
    return ref.read(screenWakeLockProvider).keepAwakeWhile(
          () => _runNapcatAction(
            action: 'restart-napcat',
            busyLabel: 'NapCat 重启中',
            instance: instance,
            run: (runtime) async {
              await _ensureNapcatReady(runtime);
              await runtime.restartProcess(
                'napcat',
                args: _napcatArgs(instance),
              );
            },
          ),
        );
  }

  /// 删除活动实例前停止它占用的全部原生进程。
  ///
  /// 与普通按钮动作不同，这个方法会把失败继续抛给删除事务，确保停止失败时不会
  /// 继续删除目录或本地记录。
  Future<void> stopActiveInstance(String instanceId) async {
    if (!state.isActiveInstance(instanceId)) return;
    if (_actionInProgress || state.isBusy) {
      throw StateError('另一个进程操作尚未完成');
    }
    _actionInProgress = true;
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(busyAction: 'delete-stop', errorMessage: null);
    try {
      if (state.botStatus != 'stopped') {
        await runtime.stopProcess('bot');
      }
      if (state.napcatStatus != 'stopped') {
        await runtime.stopProcess('napcat');
      }
      state = state.copyWith(
        status: <String, String>{
          ...state.status,
          'bot': 'stopped',
          'napcat': 'stopped',
        },
        activeInstanceId: null,
        napcatQrPayload: null,
        napcatWebuiUrl: null,
      );
      await refreshStatus();
      if (state.hasRunningProcess && state.isActiveInstance(instanceId)) {
        throw StateError('进程仍在运行');
      }
    } catch (error) {
      appLogger.e('process: stop active instance failed', error: error);
      state = state.copyWith(errorMessage: '停止实例进程失败：$error');
      rethrow;
    } finally {
      state = state.copyWith(busyAction: null);
      _actionInProgress = false;
    }
  }

  /// OOBE 允许跳过 NapCat，因此第一次真正使用它时在这里做幂等安装。
  /// 原生安装任务会检测已有文件；已安装设备只做快速校验，不会重复下载。
  Future<void> _ensureNapcatReady(RuntimeBridge runtime) async {
    const taskNames = <String>['installNapcat', 'verifyNapcat'];
    final streamedTasks = <String>{};
    final subscription = runtime
        .installEvents()
        .where(
          (event) => taskNames.contains(event.task),
        )
        .listen((event) {
      streamedTasks.add(event.task);
      _appendNapcatLog(event.line);
    });

    try {
      for (final task in taskNames) {
        final label = task == 'installNapcat' ? '准备 NapCat' : '校验 NapCat';
        _appendNapcatLog('[control] $label…');
        final result = await runtime.runInstallTask(task);
        if (!streamedTasks.contains(task)) {
          for (final line in result.logs) {
            _appendNapcatLog(line);
          }
        }
        if (!result.success) {
          throw _NapcatSetupException(result.error ?? '$label失败');
        }
        _appendNapcatLog('[control] $label完成');
      }
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> refreshStatus() async {
    try {
      final snapshot = await ref.read(runtimeBridgeProvider).processStatus();
      final status = <String, String>{
        ...state.status,
        if (snapshot['bot'] != null) 'bot': snapshot['bot']!,
        if (snapshot['napcat'] != null) 'napcat': snapshot['napcat']!,
      };
      final rawActiveInstanceId = snapshot['activeInstanceId'];
      final hasRunningProcess =
          status['bot'] == 'running' || status['napcat'] == 'running';
      final activeInstanceId = !hasRunningProcess
          ? null
          : rawActiveInstanceId != null && rawActiveInstanceId.isNotEmpty
              ? rawActiveInstanceId
              : state.activeInstanceId;
      state = state.copyWith(
        status: status,
        activeInstanceId: activeInstanceId,
        errorMessage: null,
      );
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
      'process: bot $action'
      '${instance == null ? '' : ' instance=${instance.id}'}',
    );
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(busyAction: action, errorMessage: null);
    _appendBotLog(
      '[control] $busyLabel'
      '${instance == null ? '' : '：${instance.name}'}',
    );
    try {
      await run(runtime);
      final status = <String, String>{
        ...state.status,
        'bot': action == 'stop' ? 'stopped' : 'running',
      };
      state = state.copyWith(
        status: status,
        activeInstanceId: action == 'stop'
            ? status['napcat'] == 'running'
                ? state.activeInstanceId
                : null
            : instance!.id,
      );
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
    Instance? instance,
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
      final status = <String, String>{
        ...state.status,
        'napcat': action == 'stop-napcat' ? 'stopped' : 'running',
      };
      state = state.copyWith(
        status: status,
        activeInstanceId: action == 'stop-napcat'
            ? status['bot'] == 'running'
                ? state.activeInstanceId
                : null
            : instance!.id,
        napcatWebuiUrl: action == 'stop-napcat' ? null : state.napcatWebuiUrl,
      );
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
        // NapCat 刷新二维码时会覆盖同一个 qrcode.png。附加只用于 UI 缓存键的
        // 版本号，让 Riverpod listener 能识别同路径的新图片并触发弹窗刷新。
        final version = DateTime.now().microsecondsSinceEpoch;
        final payload = 'file:$hostPath#$version';
        appLogger.i(
          'process: napcat QR from process stream (len=${payload.length})',
        );
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
        appLogger.i('process: napcat webui url detected');
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
    final safeLine = _redactSensitiveLogLine(line);
    state = state.copyWith(
      botLogs: _tail(<String>[...state.botLogs, safeLine]),
    );
  }

  void _appendNapcatLog(String line) {
    final safeLine = _redactSensitiveLogLine(line);
    state = state.copyWith(
      napcatLogs: _tail(<String>[...state.napcatLogs, safeLine]),
    );
  }

  Map<String, String> _botArgs(Instance instance) => <String, String>{
        'instanceId': instance.id,
        'repoPath': instance.repoPath,
      };

  Map<String, String> _napcatArgs(Instance instance) => <String, String>{
        'instanceId': instance.id,
        'botQq': instance.botQq,
      };

  bool _canActivate(String instanceId) {
    final activeInstanceId = state.activeInstanceId;
    if (!state.hasRunningProcess || activeInstanceId == instanceId) {
      return true;
    }
    state = state.copyWith(
      errorMessage: activeInstanceId == null
          ? '已有身份未知的进程正在运行，请先停止后再切换实例'
          : '另一个实例正在运行，请先停止后再切换实例',
    );
    return false;
  }
}

List<String> _tail(List<String> logs) {
  final start = logs.length > _maxLogs ? logs.length - _maxLogs : 0;
  return logs.sublist(start);
}

String _redactSensitiveLogLine(String line) {
  final querySecret = RegExp(
    r'([?&](?:token|access_token|api[_-]?key|secret)=)[^&\s]+',
    caseSensitive: false,
  );
  final assignedSecret = RegExp(
    r'(\b(?:token|access[_-]?token|api[_-]?key|password|secret)\s*[:=]\s*)\S+',
    caseSensitive: false,
  );
  final bearerSecret = RegExp(r'(\bBearer\s+)\S+', caseSensitive: false);
  return line
      .replaceAllMapped(querySecret, (match) => '${match.group(1)}[REDACTED]')
      .replaceAllMapped(
        assignedSecret,
        (match) => '${match.group(1)}[REDACTED]',
      )
      .replaceAllMapped(bearerSecret, (match) => '${match.group(1)}[REDACTED]');
}

const int _maxLogs = 400;

class _NapcatSetupException implements Exception {
  const _NapcatSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

final processConsoleProvider =
    NotifierProvider<ProcessConsoleNotifier, ProcessConsoleState>(
  ProcessConsoleNotifier.new,
);
