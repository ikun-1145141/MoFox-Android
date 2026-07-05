import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_gateway.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/oobe_step.dart';

class OobeFlowState {
  const OobeFlowState({
    required this.current,
    required this.result,
    this.logs = const <String>[],
  });

  final OobeStep current;
  final OobeStepResult result;

  /// `extractRuntime` 阶段的实时日志（成功后保留供翻看）。
  final List<String> logs;

  OobeFlowState copyWith({
    OobeStep? current,
    OobeStepResult? result,
    List<String>? logs,
  }) =>
      OobeFlowState(
        current: current ?? this.current,
        result: result ?? this.result,
        logs: logs ?? this.logs,
      );

  static const OobeFlowState initial = OobeFlowState(
    current: OobeStep.welcome,
    result: OobeStepPending(),
  );
}

/// 驱动 OOBE 各步的中央 Notifier。具体每一步的执行细节由对应页面注入回调，
/// Notifier 这里只管「当前是谁 / 进度如何 / 失败回退」。
class OobeFlowNotifier extends Notifier<OobeFlowState> {
  bool _runtimeInstallStarted = false;
  bool _runtimeInstallCompleted = false;
  final List<String> _pendingLogs = <String>[];
  Timer? _logFlushTimer;

  @override
  OobeFlowState build() => OobeFlowState.initial;

  void start() {
    state = state.copyWith(result: const OobeStepRunning('准备中…'));
  }

  void progress(String message) {
    state = state.copyWith(result: OobeStepRunning(message));
  }

  void completeStep() {
    final next = state.current.next();
    state = OobeFlowState(
      current: next,
      result: next == OobeStep.done
          ? const OobeStepSuccess()
          : const OobeStepPending(),
      logs: state.logs,
    );
  }

  void fail(String message, {bool recoverable = true}) {
    state = state.copyWith(
      result: OobeStepFailure(message, recoverable: recoverable),
    );
  }

  void retry() {
    state = state.copyWith(result: const OobeStepPending());
  }

  void jumpTo(OobeStep step) {
    state = OobeFlowState(
      current: step,
      result: step == OobeStep.extractRuntime && _runtimeInstallCompleted
          ? const OobeStepSuccess()
          : const OobeStepPending(),
      logs: state.logs,
    );
  }

  /// 跑 OOBE 的 extractRuntime 阶段：
  /// `extractRootfs` → `installRuntimeDeps` → `installNapcat`。
  ///
  /// 这三件全是「全局一次性」的事情。每次只跑一遍，靠 `_runtimeInstallStarted`
  /// 防止用户来回切步骤导致重入。失败后会把 flag 重置，按重试按钮可以再来一次。
  Future<void> runRuntimeInstall() async {
    if (_runtimeInstallCompleted) {
      state = state.copyWith(result: const OobeStepSuccess());
      return;
    }
    if (_runtimeInstallStarted) return;
    _runtimeInstallStarted = true;
    appLogger.i('oobe: runRuntimeInstall start');

    final platform = ref.read(platformGatewayProvider);
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(
      result: const OobeStepRunning('解压运行环境…'),
      logs: <String>['[info] 开始安装 MoFox 运行环境'],
    );
    _pendingLogs.clear();

    final logSub = runtime.installEvents().listen((event) {
      _appendLog(event.line);
    });

    try {
      await _setKeepScreenOn(platform, enabled: true);
      const tasks = <_RuntimeTask>[
        _RuntimeTask(name: 'extractRootfs', label: '解压 Debian 13 rootfs'),
        _RuntimeTask(name: 'installRuntimeDeps', label: '安装 apt 基础依赖'),
        _RuntimeTask(name: 'installNapcat', label: '安装全局 NapCat'),
      ];
      for (final task in tasks) {
        state = state.copyWith(result: OobeStepRunning(task.label));
        _appendLog('[run] ${task.label}…');
        appLogger.i('oobe: run task=${task.name}');
        final result = await runtime.runInstallTask(task.name);
        if (!result.success) {
          final msg = result.error ?? '${task.label} 失败';
          appLogger.e('oobe: task=${task.name} failed: $msg');
          _appendLog('[error] $msg');
          _flushLogs();
          _runtimeInstallStarted = false;
          state = state.copyWith(
            result: OobeStepFailure(msg),
          );
          return;
        }
        _appendLog('[ok] ${task.label} 完成');
      }
      _appendLog('[done] 运行环境就绪');
      _flushLogs();
      _runtimeInstallCompleted = true;
      appLogger.i('oobe: runtime install completed');
      state = state.copyWith(result: const OobeStepSuccess());
    } on PlatformException catch (e) {
      final msg = e.message ?? '原生错误 (${e.code})';
      appLogger.e('oobe: PlatformException', error: e);
      _appendLog('[error] $msg');
      _flushLogs();
      _runtimeInstallStarted = false;
      state = state.copyWith(result: OobeStepFailure(msg));
    } catch (e) {
      appLogger.e('oobe: runtime install error', error: e);
      _appendLog('[error] $e');
      _flushLogs();
      _runtimeInstallStarted = false;
      state = state.copyWith(result: OobeStepFailure(e.toString()));
    } finally {
      await logSub.cancel();
      await _setKeepScreenOn(platform, enabled: false);
      _flushLogs();
    }
  }

  Future<void> _setKeepScreenOn(
    PlatformGateway platform, {
    required bool enabled,
  }) async {
    try {
      await platform.setKeepScreenOn(enabled: enabled);
    } catch (_) {
      // Screen wakefulness is best-effort; runtime install should keep going.
    }
  }

  void _appendLog(String line) {
    _pendingLogs.add(_trimLogLine(line));
    _logFlushTimer ??= Timer(const Duration(milliseconds: 200), _flushLogs);
  }

  void _flushLogs() {
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    if (_pendingLogs.isEmpty) return;
    final next = <String>[...state.logs, ..._pendingLogs];
    _pendingLogs.clear();
    final start = next.length > _maxRuntimeLogLines
        ? next.length - _maxRuntimeLogLines
        : 0;
    state = state.copyWith(logs: next.sublist(start));
  }
}

String _trimLogLine(String line) {
  if (line.length <= _maxRuntimeLogLineChars) return line;
  return '${line.substring(0, _maxRuntimeLogLineChars)}…';
}

const int _maxRuntimeLogLines = 300;
const int _maxRuntimeLogLineChars = 600;

class _RuntimeTask {
  const _RuntimeTask({required this.name, required this.label});
  final String name;
  final String label;
}

final oobeFlowProvider =
    NotifierProvider<OobeFlowNotifier, OobeFlowState>(OobeFlowNotifier.new);
