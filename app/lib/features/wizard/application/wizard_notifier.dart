import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_bridge.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';
import '../domain/wizard_step.dart';

class WizardState {
  const WizardState({
    required this.step,
    required this.draft,
    required this.taskStatus,
    required this.taskProgress,
    required this.logs,
    this.errorMessage,
    this.napcatQrPayload,
    this.installFinished = false,
  });

  final WizardStep step;
  final InstanceDraft draft;

  /// 每个 install task 的状态。
  final Map<InstallTask, InstallTaskStatus> taskStatus;

  /// 当前正在跑的 task 的 0..1 进度。
  final double taskProgress;

  /// 安装日志（最新在末尾）。
  final List<String> logs;

  /// 整体错误（致命）。
  final String? errorMessage;

  /// NapCat 扫码二维码 payload。null = 还没拿到。
  final String? napcatQrPayload;

  /// 安装是否全部完成。
  final bool installFinished;

  WizardState copyWith({
    WizardStep? step,
    InstanceDraft? draft,
    Map<InstallTask, InstallTaskStatus>? taskStatus,
    double? taskProgress,
    List<String>? logs,
    String? errorMessage,
    Object? napcatQrPayload = _sentinel,
    bool? installFinished,
  }) =>
      WizardState(
        step: step ?? this.step,
        draft: draft ?? this.draft,
        taskStatus: taskStatus ?? this.taskStatus,
        taskProgress: taskProgress ?? this.taskProgress,
        logs: logs ?? this.logs,
        errorMessage: errorMessage ?? this.errorMessage,
        napcatQrPayload: identical(napcatQrPayload, _sentinel)
            ? this.napcatQrPayload
            : napcatQrPayload as String?,
        installFinished: installFinished ?? this.installFinished,
      );

  /// 当前任务（第一个 running 或 pending 的 task）。
  InstallTask? get currentTask {
    for (final t in InstallTask.values) {
      final s = taskStatus[t] ?? InstallTaskStatus.pending;
      if (s == InstallTaskStatus.running) return t;
    }
    for (final t in InstallTask.values) {
      final s = taskStatus[t] ?? InstallTaskStatus.pending;
      if (s == InstallTaskStatus.pending) return t;
    }
    return null;
  }

  /// 整体进度 0..1。
  double get overallProgress {
    final total = InstallTask.values.length;
    final done = taskStatus.values
        .where(
          (s) =>
              s == InstallTaskStatus.success || s == InstallTaskStatus.skipped,
        )
        .length;
    return (done + taskProgress) / total;
  }
}

const Object _sentinel = Object();

class WizardNotifier extends Notifier<WizardState> {
  Timer? _runner;

  @override
  WizardState build() {
    ref.onDispose(() => _runner?.cancel());
    return WizardState(
      step: WizardStep.instanceInfo,
      draft: const InstanceDraft(),
      taskStatus: <InstallTask, InstallTaskStatus>{
        for (final t in InstallTask.values) t: InstallTaskStatus.pending,
      },
      taskProgress: 0,
      logs: const <String>[],
    );
  }

  // ---- 表单操作 ----

  void update(InstanceDraft Function(InstanceDraft) f) {
    state = state.copyWith(draft: f(state.draft));
  }

  void goTo(WizardStep step) {
    state = state.copyWith(step: step);
  }

  bool nextStep() {
    final next = state.step.next();
    if (next == null) return false;
    state = state.copyWith(step: next);
    return true;
  }

  bool prevStep() {
    final prev = state.step.prev();
    if (prev == null) return false;
    state = state.copyWith(step: prev);
    return true;
  }

  // ---- 安装执行 ----

  /// 启动安装流程。原生层负责 rootfs/proot/脚本执行，Flutter 负责状态编排。
  Future<void> startInstall() async {
    _runner?.cancel();
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(
      taskStatus: <InstallTask, InstallTaskStatus>{
        for (final t in InstallTask.values) t: InstallTaskStatus.pending,
      },
      taskProgress: 0,
      logs: <String>['[info] 准备安装环境…'],
      napcatQrPayload: null,
      installFinished: false,
    );

    for (final task in InstallTask.values) {
      // 跳过：用户没勾选 NapCat / WebUI 时
      if (task == InstallTask.installNapcat && !state.draft.installNapcat) {
        _markStatus(task, InstallTaskStatus.skipped);
        _appendLog('[skip] 已跳过 NapCat 安装');
        continue;
      }
      if (task == InstallTask.napcatLogin && !state.draft.installNapcat) {
        _markStatus(task, InstallTaskStatus.skipped);
        continue;
      }
      if (task == InstallTask.writeNapcatConfig && !state.draft.installNapcat) {
        _markStatus(task, InstallTaskStatus.skipped);
        continue;
      }
      if (task == InstallTask.installWebui && !state.draft.installWebui) {
        _markStatus(task, InstallTaskStatus.skipped);
        _appendLog('[skip] 已跳过 WebUI 安装');
        continue;
      }

      _markStatus(task, InstallTaskStatus.running);
      _appendLog('[run] ${task.label}…');

      final nativeTask = _nativeTaskName(task);
      if (nativeTask != null) {
        state = state.copyWith(taskProgress: 0.35);
        final streamedLogs = <String>[];
        final logSubscription = runtime.installTaskLogs(nativeTask).listen(
          (line) {
            streamedLogs.add(line);
            _appendLog(line);
          },
        );
        final result = await runtime.runInstallTask(
          nativeTask,
          args: _runtimeArgs(),
        );
        await logSubscription.cancel();
        if (streamedLogs.isEmpty) {
          _appendLogs(result.logs);
        }
        if (!result.success) {
          _markStatus(task, InstallTaskStatus.failed);
          final message = result.error ?? '${task.label} 执行失败';
          state = state.copyWith(errorMessage: message, taskProgress: 0);
          _appendLog('[error] $message');
          return;
        }
        state = state.copyWith(taskProgress: 1);

        if (result.qrPayload != null) {
          state = state.copyWith(napcatQrPayload: result.qrPayload);
        }
      }

      if (task == InstallTask.napcatLogin) {
        _appendLog('[info] NapCat 登录需要通过 NapCat WebUI 完成');
        state = state.copyWith(napcatQrPayload: null);
      }

      // 注册实例：真正写入仓库
      if (task == InstallTask.registerInstance) {
        final repo = await ref.read(instanceRepositoryProvider.future);
        final draft = state.draft;
        await repo.add(
          Instance(
            id: 'inst-${DateTime.now().millisecondsSinceEpoch}',
            name: draft.name.isEmpty ? '未命名实例' : draft.name,
            botQq: draft.botQq,
            botNickname: draft.botNickname,
            ownerQq: draft.ownerQq,
            wsPort: draft.wsPort,
            channel: draft.channel,
            installNapcat: draft.installNapcat,
            installWebui: draft.installWebui,
            createdAt: DateTime.now(),
          ),
        );
        ref.invalidate(instancesProvider);
        _appendLog('[ok] 实例已注册到本地');
      }

      _markStatus(task, InstallTaskStatus.success);
      state = state.copyWith(taskProgress: 0);
      _appendLog('[ok] ${task.label} 完成');
    }

    state = state.copyWith(installFinished: true);
    _appendLog('[done] 安装全部完成');
  }

  String? _nativeTaskName(InstallTask task) => switch (task) {
        InstallTask.extractRootfs => 'extractRootfs',
        InstallTask.installRuntimeDeps => 'installRuntimeDeps',
        InstallTask.cloneRepo => 'cloneRepo',
        InstallTask.syncDeps => 'syncDeps',
        InstallTask.genConfig => 'genConfig',
        InstallTask.writeCore => 'writeCore',
        InstallTask.writeModel => 'writeModel',
        InstallTask.writeAdapter => 'writeAdapter',
        InstallTask.installWebui => 'installWebui',
        InstallTask.installNapcat => 'installNapcat',
        InstallTask.napcatLogin => 'napcatLogin',
        InstallTask.writeNapcatConfig => 'writeNapcatConfig',
        InstallTask.registerInstance => null,
      };

  Map<String, String> _runtimeArgs() {
    final draft = state.draft;
    return <String, String>{
      'name': draft.name,
      'botQq': draft.botQq,
      'botNickname': draft.botNickname,
      'ownerQq': draft.ownerQq,
      'apiKey': draft.apiKey,
      'apiBaseUrl': draft.apiBaseUrl,
      'wsPort': draft.wsPort.toString(),
      'channel': draft.channel,
      'webuiApiKey': draft.webuiApiKey,
      'installNapcat': draft.installNapcat.toString(),
      'installWebui': draft.installWebui.toString(),
    };
  }

  void _markStatus(InstallTask task, InstallTaskStatus status) {
    final next = <InstallTask, InstallTaskStatus>{...state.taskStatus};
    next[task] = status;
    state = state.copyWith(taskStatus: next);
  }

  void _appendLog(String line) {
    state = state.copyWith(logs: <String>[...state.logs, line]);
  }

  void _appendLogs(List<String> lines) {
    if (lines.isEmpty) return;
    state = state.copyWith(logs: <String>[...state.logs, ...lines]);
  }
}

final wizardProvider =
    NotifierProvider<WizardNotifier, WizardState>(WizardNotifier.new);
