import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/screen_wake_lock.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/oobe_step.dart';

class OobeFlowState {
  const OobeFlowState({
    required this.current,
    required this.result,
    required this.installNapcat,
    this.logs = const <String>[],
  });

  final OobeStep current;
  final OobeStepResult result;

  /// 是否在首次初始化时一并安装 NapCat。默认关闭，必须由用户主动选择。
  final bool installNapcat;

  /// `extractRuntime` 阶段的实时日志（成功后保留供翻看）。
  final List<String> logs;

  OobeFlowState copyWith({
    OobeStep? current,
    OobeStepResult? result,
    bool? installNapcat,
    List<String>? logs,
  }) =>
      OobeFlowState(
        current: current ?? this.current,
        result: result ?? this.result,
        installNapcat: installNapcat ?? this.installNapcat,
        logs: logs ?? this.logs,
      );

  static const OobeFlowState initial = OobeFlowState(
    current: OobeStep.welcome,
    result: OobeStepPending(),
    installNapcat: false,
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
      installNapcat: state.installNapcat,
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
      installNapcat: state.installNapcat,
      logs: state.logs,
    );
  }

  /// 修改可选组件。安装执行期间或完成后锁定，避免任务计划与界面选择不一致。
  void setInstallNapcat(bool value) {
    if (_runtimeInstallStarted || _runtimeInstallCompleted) return;
    state = state.copyWith(installNapcat: value);
  }

  /// 跑 OOBE 的 extractRuntime 阶段：
  /// 始终执行 `extractRootfs` → `installRuntimeDeps`；只有用户显式选择时才继续
  /// `installNapcat` → `verifyNapcat`。
  ///
  /// 这些全是「全局一次性」的事情。每次只跑一遍，靠 `_runtimeInstallStarted`
  /// 防止用户来回切步骤导致重入。失败后会把 flag 重置，按重试按钮可以再来一次。
  Future<void> runRuntimeInstall() async {
    if (_runtimeInstallCompleted) {
      state = state.copyWith(result: const OobeStepSuccess());
      return;
    }
    if (_runtimeInstallStarted) return;
    _runtimeInstallStarted = true;
    final installNapcat = state.installNapcat;
    appLogger.i(
      'oobe: runRuntimeInstall start installNapcat=$installNapcat',
    );

    final wakeLock = ref.read(screenWakeLockProvider);
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(
      result: const OobeStepRunning('解压运行环境…'),
      logs: <String>[
        '[info] 开始安装 MoFox 运行环境',
        if (!installNapcat) '[info] 已选择跳过可选组件 NapCat',
      ],
    );
    _pendingLogs.clear();
    StreamSubscription<InstallEvent>? logSub;

    try {
      await wakeLock.acquire();
      logSub = runtime.installEvents().listen((event) {
        _appendLog(event.line);
      });
      final tasks = oobeRuntimeTasks(installNapcat: installNapcat);
      for (final task in tasks) {
        state = state.copyWith(result: OobeStepRunning(task.label));
        _appendLog('[run] ${task.label}…');
        appLogger.i('oobe: run task=${task.nativeName}');
        final result = await runtime.runInstallTask(task.nativeName);
        if (!result.success) {
          final msg = result.error ?? '${task.label} 失败';
          appLogger.e('oobe: task=${task.nativeName} failed: $msg');
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
      _appendLog(
        installNapcat
            ? '[done] 运行环境和 NapCat 已就绪'
            : '[done] 基础运行环境已就绪（未安装 NapCat）',
      );
      _flushLogs();
      _runtimeInstallCompleted = true;
      appLogger.i(
        'oobe: runtime install completed installNapcat=$installNapcat',
      );
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
      try {
        await logSub?.cancel();
      } finally {
        try {
          await wakeLock.release();
        } finally {
          _flushLogs();
        }
      }
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

final oobeFlowProvider =
    NotifierProvider<OobeFlowNotifier, OobeFlowState>(OobeFlowNotifier.new);
