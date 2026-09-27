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
    required this.snowlumaLogs,
    this.activeInstanceId,
    this.busyAction,
    this.errorMessage,
    this.snowlumaQrPayload,
    this.snowlumaWebuiUrl,
  });

  factory ProcessConsoleState.initial() => const ProcessConsoleState(
        status: <String, String>{'bot': 'stopped', 'snowluma': 'stopped'},
        botLogs: <String>[],
        snowlumaLogs: <String>[],
      );

  final Map<String, String> status;
  final List<String> botLogs;
  final List<String> snowlumaLogs;

  /// 当前占用原生单实例进程槽位的实例。
  ///
  /// Bot 与 SnowLuma 的原生托管器都是全局唯一的，因此裸的 [botStatus] / [snowlumaStatus]
  /// 不能直接用于任意实例卡片。界面应通过 [botStatusFor] / [snowlumaStatusFor]
  /// 读取实例作用域内的状态。
  final String? activeInstanceId;
  final String? busyAction;
  final String? errorMessage;
  final String? snowlumaQrPayload;

  /// SnowLuma WebUI 地址（含 token），从 snowluma 日志解析。
  /// 形如 `http://127.0.0.1:5099/?token=xxx`。
  final String? snowlumaWebuiUrl;

  bool get isBusy => busyAction != null;
  String get botStatus => status['bot'] ?? 'stopped';
  String get snowlumaStatus => status['snowluma'] ?? 'stopped';

  bool get hasRunningProcess =>
      botStatus == 'running' || snowlumaStatus == 'running';

  bool isActiveInstance(String instanceId) =>
      activeInstanceId != null && activeInstanceId == instanceId;

  String botStatusFor(String instanceId) =>
      isActiveInstance(instanceId) ? botStatus : 'stopped';

  String snowlumaStatusFor(String instanceId) =>
      isActiveInstance(instanceId) ? snowlumaStatus : 'stopped';

  ProcessConsoleState copyWith({
    Map<String, String>? status,
    List<String>? botLogs,
    List<String>? snowlumaLogs,
    Object? activeInstanceId = _sentinel,
    Object? busyAction = _sentinel,
    Object? errorMessage = _sentinel,
    Object? snowlumaQrPayload = _sentinel,
    Object? snowlumaWebuiUrl = _sentinel,
  }) =>
      ProcessConsoleState(
        status: status ?? this.status,
        botLogs: botLogs ?? this.botLogs,
        snowlumaLogs: snowlumaLogs ?? this.snowlumaLogs,
        activeInstanceId: identical(activeInstanceId, _sentinel)
            ? this.activeInstanceId
            : activeInstanceId as String?,
        busyAction: identical(busyAction, _sentinel)
            ? this.busyAction
            : busyAction as String?,
        errorMessage: identical(errorMessage, _sentinel)
            ? this.errorMessage
            : errorMessage as String?,
        snowlumaQrPayload: identical(snowlumaQrPayload, _sentinel)
            ? this.snowlumaQrPayload
            : snowlumaQrPayload as String?,
        snowlumaWebuiUrl: identical(snowlumaWebuiUrl, _sentinel)
            ? this.snowlumaWebuiUrl
            : snowlumaWebuiUrl as String?,
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

  Future<void> startSnowluma(Instance instance) {
    if (!_canActivate(instance.id)) return Future<void>.value();
    appLogger.i(
      'process: startSnowluma instance=${instance.id}',
    );
    return ref.read(screenWakeLockProvider).keepAwakeWhile(
          () => _runSnowlumaAction(
            action: 'start-snowluma',
            busyLabel: 'SnowLuma 启动中',
            instance: instance,
            run: (runtime) async {
              await _ensureSnowlumaReady(runtime);
              final args = _snowlumaArgs(instance);
              appLogger.i('process: starting snowluma process');
              await runtime.startProcess('snowluma', args: args);
              // 给 snowluma 进程 2 秒稳定时间，避免 refreshStatus 读到刚启动还未就绪的状态
              await Future<void>.delayed(const Duration(seconds: 2));
            },
          ),
        );
  }

  Future<void> stopSnowluma() => _runSnowlumaAction(
        action: 'stop-snowluma',
        busyLabel: 'SnowLuma 停止中',
        run: (runtime) => runtime.stopProcess('snowluma'),
      );

  /// 取消正在进行的 SnowLuma 扫码登录。
  /// 新流程中 SnowLuma 进程直接启动，取消登录 = 停止 snowluma 进程。
  /// 不在这里清 snowlumaQrPayload——由调用方在 pop sheet 后清，
  /// 避免此处 setState 触发 listener 在 sheet 关闭动画中二次 pop 导致崩溃。
  Future<void> cancelSnowlumaLogin() async {
    appLogger.i('process: cancelSnowlumaLogin (stop snowluma process)');
    final runtime = ref.read(runtimeBridgeProvider);
    try {
      await runtime.stopProcess('snowluma');
      final status = <String, String>{
        ...state.status,
        'snowluma': 'stopped',
      };
      state = state.copyWith(
        status: status,
        activeInstanceId:
            status['bot'] == 'running' ? state.activeInstanceId : null,
      );
      await refreshStatus();
    } catch (error) {
      appLogger.e('process: cancelSnowlumaLogin failed', error: error);
    }
  }

  Future<void> restartSnowluma(Instance instance) {
    if (!_canActivate(instance.id)) return Future<void>.value();
    return ref.read(screenWakeLockProvider).keepAwakeWhile(
          () => _runSnowlumaAction(
            action: 'restart-snowluma',
            busyLabel: 'SnowLuma 重启中',
            instance: instance,
            run: (runtime) async {
              await _ensureSnowlumaReady(runtime);
              await runtime.restartProcess(
                'snowluma',
                args: _snowlumaArgs(instance),
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
      if (state.snowlumaStatus != 'stopped') {
        await runtime.stopProcess('snowluma');
      }
      state = state.copyWith(
        status: <String, String>{
          ...state.status,
          'bot': 'stopped',
          'snowluma': 'stopped',
        },
        activeInstanceId: null,
        snowlumaQrPayload: null,
        snowlumaWebuiUrl: null,
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

  /// OOBE 允许跳过 SnowLuma，因此第一次真正使用它时在这里做幂等安装。
  /// 原生安装任务会检测已有文件；已安装设备只做快速校验，不会重复下载。
  Future<void> _ensureSnowlumaReady(RuntimeBridge runtime) async {
    const taskNames = <String>['installSnowluma', 'verifySnowluma'];
    final streamedTasks = <String>{};
    final subscription = runtime
        .installEvents()
        .where(
          (event) => taskNames.contains(event.task),
        )
        .listen((event) {
      streamedTasks.add(event.task);
      _appendSnowlumaLog(event.line);
    });

    try {
      for (final task in taskNames) {
        final label = task == 'installSnowluma' ? '准备 SnowLuma' : '校验 SnowLuma';
        _appendSnowlumaLog('[control] $label…');
        final result = await runtime.runInstallTask(task);
        if (!streamedTasks.contains(task)) {
          for (final line in result.logs) {
            _appendSnowlumaLog(line);
          }
        }
        if (!result.success) {
          throw _SnowlumaSetupException(result.error ?? '$label失败');
        }
        _appendSnowlumaLog('[control] $label完成');
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
        if (snapshot['snowluma'] != null) 'snowluma': snapshot['snowluma']!,
      };
      final rawActiveInstanceId = snapshot['activeInstanceId'];
      final hasRunningProcess =
          status['bot'] == 'running' || status['snowluma'] == 'running';
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
            ? status['snowluma'] == 'running'
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

  Future<void> _runSnowlumaAction({
    required String action,
    required String busyLabel,
    required Future<void> Function(RuntimeBridge runtime) run,
    Instance? instance,
  }) async {
    if (_actionInProgress || state.isBusy) return;
    _actionInProgress = true;
    appLogger.i('process: snowluma $action');
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(
      busyAction: action,
      errorMessage: null,
      snowlumaQrPayload: null,
    );
    _appendSnowlumaLog('[control] $busyLabel');
    try {
      await run(runtime);
      final status = <String, String>{
        ...state.status,
        'snowluma': action == 'stop-snowluma' ? 'stopped' : 'running',
      };
      state = state.copyWith(
        status: status,
        activeInstanceId: action == 'stop-snowluma'
            ? status['bot'] == 'running'
                ? state.activeInstanceId
                : null
            : instance!.id,
        snowlumaWebuiUrl:
            action == 'stop-snowluma' ? null : state.snowlumaWebuiUrl,
      );
      await refreshStatus();
    } catch (error) {
      appLogger.e('process: snowluma $action failed', error: error);
      state = state.copyWith(
        errorMessage: '$busyLabel失败：$error',
        snowlumaQrPayload: null,
      );
      _appendSnowlumaLog('[control] $busyLabel失败：$error');
    } finally {
      state = state.copyWith(busyAction: null);
      _actionInProgress = false;
    }
  }

  /// 把 UI 侧的弹窗决策写进 SnowLuma 日志 Tab。
  /// 真机上没有 adb 时，这是唯一能看到"弹窗为什么开/关"的窗口。
  void appendSnowlumaNote(String message) {
    _appendSnowlumaLog('[ui] $message');
  }

  /// 快捷登录：向虚拟屏幕里的 QQ 窗口发送回车，触发 QQ 的"登录"默认按钮。
  /// QQ 记住账号时启动显示的是快捷登录窗口而非二维码，需要这一步。
  Future<void> quickLoginQq() async {
    final runtime = ref.read(runtimeBridgeProvider);
    _appendSnowlumaLog('[control] 发送快捷登录指令…');
    try {
      final result = await runtime.runInstallTask('qqQuickLogin');
      for (final line in result.logs) {
        _appendSnowlumaLog(line);
      }
      if (!result.success) {
        _appendSnowlumaLog('[control] 快捷登录指令失败: ${result.error}');
      }
    } on Object catch (error) {
      _appendSnowlumaLog('[control] 快捷登录指令异常: $error');
    }
    unawaited(refreshStatus());
  }

  void _onProcessEvent(ProcessEvent event) {
    if (event.name == 'bot') {
      _appendBotLog(event.line);
    } else if (event.name == 'snowluma') {
      // 检测 QR 码标记行：进程脚本后台监控 QR 文件并输出 MOFOX_QR_IMAGE=<path>
      if (event.line.startsWith('MOFOX_QR_IMAGE=')) {
        final hostPath = event.line.substring('MOFOX_QR_IMAGE='.length);
        // SnowLuma 刷新二维码时会覆盖同一个 screen.png。附加只用于 UI 缓存键的
        // 版本号，让 Riverpod listener 能识别同路径的新图片并触发弹窗刷新。
        final version = DateTime.now().microsecondsSinceEpoch;
        final payload = 'file:$hostPath#$version';
        appLogger.i(
          'process: snowluma QR from process stream (len=${payload.length})',
        );
        // 先更新 payload 再写日志：日志触发的 listener 重入要能看到新 payload，
        // 否则会按"payload 已清除"的错误理由把刚要打开的弹窗又收起。
        state = state.copyWith(snowlumaQrPayload: payload);
        _appendSnowlumaLog('[control] 检测到二维码截图更新 (v$version)');
        return;
      }
      // 登录成功标记：旧版靠日志里的「配置加载」，新版原生直接给 MOFOX_LOGIN_OK=
      if (event.line.contains('配置加载') ||
          event.line.startsWith('MOFOX_LOGIN_OK=')) {
        appLogger.i('process: snowluma login success detected');
        state = state.copyWith(snowlumaQrPayload: null);
      }
      // 解析 SnowLuma WebUI 地址（含 token）
      // 新版原生直接输出 MOFOX_WEBUI_URL=<url>；旧版日志形如：
      // [WebUi] WebUi User Panel Url: http://127.0.0.1:5099/?token=xxx
      final mofoxWebuiMatch = RegExp(
        r'MOFOX_WEBUI_URL=(https?://\S+)',
      ).firstMatch(event.line);
      final webuiMatch = mofoxWebuiMatch ??
          RegExp(
            r'WebUi User Panel Url:\s*(https?://[^\s]+)',
          ).firstMatch(event.line);
      if (webuiMatch != null) {
        final url = webuiMatch.group(1)!;
        appLogger.i('process: snowluma webui url detected');
        state = state.copyWith(snowlumaWebuiUrl: url);
      }
      _appendSnowlumaLog(event.line);
    }
    if (event.line.contains('exited with')) {
      // 进程退出时清理对应的 WebUI 地址与二维码 payload，
      // 避免下次启动后弹窗直接展示上一轮的过期二维码。
      if (event.name == 'snowluma') {
        state = state.copyWith(
          snowlumaWebuiUrl: null,
          snowlumaQrPayload: null,
        );
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

  void _appendSnowlumaLog(String line) {
    final safeLine = _redactSensitiveLogLine(line);
    state = state.copyWith(
      snowlumaLogs: _tail(<String>[...state.snowlumaLogs, safeLine]),
    );
  }

  Map<String, String> _botArgs(Instance instance) => <String, String>{
        'instanceId': instance.id,
        'repoPath': instance.repoPath,
      };

  Map<String, String> _snowlumaArgs(Instance instance) => <String, String>{
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

class _SnowlumaSetupException implements Exception {
  const _SnowlumaSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

final processConsoleProvider =
    NotifierProvider<ProcessConsoleNotifier, ProcessConsoleState>(
  ProcessConsoleNotifier.new,
);
