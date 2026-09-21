import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/screen_wake_lock.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/security/webui_key_store.dart';
import '../../../core/utils/app_logger.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';
import '../domain/wizard_mirror_source.dart';
import '../domain/wizard_step.dart';
import 'wizard_install_checkpoint_store.dart';

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
    this.installStarted = false,
    this.installRunning = false,
    this.resumeAvailable = false,
    this.resumeLoading = false,
    this.requiresReconfiguration = false,
    this.instanceId,
    this.installDir,
  });

  final WizardStep step;
  final InstanceDraft draft;
  final Map<InstallTask, InstallTaskStatus> taskStatus;
  final double taskProgress;
  final List<String> logs;
  final String? errorMessage;
  final String? napcatQrPayload;
  final bool installFinished;
  final bool installStarted;

  /// 真实安装 Future 尚未结束。此状态同时用于禁用退出和所有表单修改。
  final bool installRunning;

  /// 已有加密断点，允许继续失败任务。
  final bool resumeAvailable;

  /// 正在从加密存储读取断点。
  final bool resumeLoading;

  /// 旧实例没有完整断点，必须重新确认配置，不能声称可从断点续装。
  final bool requiresReconfiguration;
  final String? instanceId;
  final String? installDir;

  WizardState copyWith({
    WizardStep? step,
    InstanceDraft? draft,
    Map<InstallTask, InstallTaskStatus>? taskStatus,
    double? taskProgress,
    List<String>? logs,
    Object? errorMessage = _sentinel,
    Object? napcatQrPayload = _sentinel,
    bool? installFinished,
    bool? installStarted,
    bool? installRunning,
    bool? resumeAvailable,
    bool? resumeLoading,
    bool? requiresReconfiguration,
    Object? instanceId = _sentinel,
    Object? installDir = _sentinel,
  }) =>
      WizardState(
        step: step ?? this.step,
        draft: draft ?? this.draft,
        taskStatus: taskStatus ?? this.taskStatus,
        taskProgress: taskProgress ?? this.taskProgress,
        logs: logs ?? this.logs,
        errorMessage: identical(errorMessage, _sentinel)
            ? this.errorMessage
            : errorMessage as String?,
        napcatQrPayload: identical(napcatQrPayload, _sentinel)
            ? this.napcatQrPayload
            : napcatQrPayload as String?,
        installFinished: installFinished ?? this.installFinished,
        installStarted: installStarted ?? this.installStarted,
        installRunning: installRunning ?? this.installRunning,
        resumeAvailable: resumeAvailable ?? this.resumeAvailable,
        resumeLoading: resumeLoading ?? this.resumeLoading,
        requiresReconfiguration:
            requiresReconfiguration ?? this.requiresReconfiguration,
        instanceId: identical(instanceId, _sentinel)
            ? this.instanceId
            : instanceId as String?,
        installDir: identical(installDir, _sentinel)
            ? this.installDir
            : installDir as String?,
      );

  InstallTask? get currentTask {
    for (final task in InstallTask.values) {
      if (taskStatus[task] == InstallTaskStatus.running) return task;
    }
    for (final task in InstallTask.values) {
      if ((taskStatus[task] ?? InstallTaskStatus.pending) ==
          InstallTaskStatus.pending) {
        return task;
      }
    }
    return null;
  }

  double get overallProgress {
    final done = taskStatus.values
        .where(
          (status) =>
              status == InstallTaskStatus.success ||
              status == InstallTaskStatus.skipped,
        )
        .length;
    return (done + taskProgress) / InstallTask.values.length;
  }
}

const Object _sentinel = Object();

class WizardNotifier extends Notifier<WizardState> {
  bool _installRunning = false;
  int _resumeLoadGeneration = 0;

  @override
  WizardState build() => _initialState();

  WizardState _initialState() => WizardState(
        step: WizardStep.mirrorCheck,
        draft: const InstanceDraft(),
        taskStatus: _pendingStatuses(),
        taskProgress: 0,
        logs: const <String>[],
      );

  void resetForNewInstance() {
    if (_installRunning || state.installRunning) {
      appLogger.w('wizard: ignored reset while installation is running');
      return;
    }
    _resumeLoadGeneration++;
    appLogger.i('wizard: resetForNewInstance');
    state = _initialState();
  }

  void update(InstanceDraft Function(InstanceDraft) updateDraft) {
    if (state.installRunning) return;
    state = state.copyWith(draft: updateDraft(state.draft));
  }

  void goTo(WizardStep step) {
    if (state.installRunning) return;
    state = state.copyWith(step: step);
  }

  bool nextStep() {
    if (state.installRunning) return false;
    final next = state.step.next();
    if (next == null) return false;
    state = state.copyWith(step: next);
    return true;
  }

  bool prevStep() {
    if (state.installRunning) return false;
    final previous = state.step.prev();
    if (previous == null) return false;
    state = state.copyWith(step: previous);
    return true;
  }

  /// 只从与该实例绑定的加密断点恢复。没有断点时清空所有密钥并回到配置流程。
  Future<void> prepareResume(Instance instance) async {
    if (_installRunning || state.installRunning) return;
    final generation = ++_resumeLoadGeneration;
    appLogger.i(
      'wizard: prepareResume instance=${instance.id} '
      'name=${instance.name} dir=${instance.installDir}',
    );

    final safeDraft = InstanceDraft(
      name: instance.name,
      botQq: instance.botQq,
      botNickname: instance.botNickname,
      ownerQq: instance.ownerQq,
      wsPort: instance.wsPort,
      channel: instance.channel,
      installWebui: instance.installWebui,
    );
    state = _initialState().copyWith(
      draft: safeDraft,
      resumeLoading: true,
      instanceId: instance.id,
      installDir: instance.installDir,
      logs: <String>[
        '[info] 正在读取实例 ${instance.name} 的加密安装断点…',
      ],
    );

    WizardInstallCheckpoint? checkpoint;
    Object? checkpointError;
    try {
      checkpoint = await ref
          .read(wizardInstallCheckpointStoreProvider)
          .read(instance.id);
    } on Object catch (error, stack) {
      checkpointError = error;
      appLogger.e(
        'wizard: failed to read install checkpoint',
        error: error,
        stackTrace: stack,
      );
    }
    if (generation != _resumeLoadGeneration) return;

    final validCheckpoint = checkpoint != null &&
        checkpoint.instanceId == instance.id &&
        checkpoint.installDir == instance.installDir &&
        checkpoint.draft.apiKey.trim().isNotEmpty;
    if (!validCheckpoint) {
      state = state.copyWith(
        resumeLoading: false,
        requiresReconfiguration: true,
        resumeAvailable: false,
        logs: <String>[
          ...state.logs,
          if (checkpointError != null)
            '[warn] 安装断点读取失败：$checkpointError'
          else
            '[warn] 未找到完整安装断点，不能安全地从失败处继续。',
          '[info] 已清空敏感字段，请重新确认镜像、协议和模型密钥。',
        ],
      );
      return;
    }

    state = state.copyWith(
      step: WizardStep.install,
      draft: checkpoint.draft,
      taskStatus: _resumeStatuses(checkpoint.taskStatus),
      taskProgress: 0,
      logs: <String>[
        '[info] 已载入实例 ${instance.name} 的加密安装断点。',
        '[info] 实例目录：${instance.installDir}',
        if (instance.installError != null)
          '[last-error] ${instance.installError}',
      ],
      errorMessage: instance.installError,
      napcatQrPayload: null,
      installFinished: false,
      installStarted: true,
      installRunning: false,
      resumeAvailable: true,
      resumeLoading: false,
      requiresReconfiguration: false,
      instanceId: instance.id,
      installDir: instance.installDir,
    );
  }

  /// 启动安装。配置在第一个 await 前冻结，后续任务只使用该快照。
  Future<void> startInstall({bool resume = false, bool restart = false}) async {
    if (_installRunning || state.installRunning || state.resumeLoading) return;
    _installRunning = true;
    _resumeLoadGeneration++;

    final installDraft = state.draft;
    final instanceId = resume && state.instanceId != null
        ? state.instanceId!
        : 'inst-${DateTime.now().millisecondsSinceEpoch}';
    final installDir = resume && state.installDir != null
        ? state.installDir!
        : '/root/instances/$instanceId';
    final initialStatuses = resume && !restart
        ? _resumeStatuses(state.taskStatus)
        : _pendingStatuses();
    final previousLogs = state.logs;
    final runtime = ref.read(runtimeBridgeProvider);
    final wakeLock = ref.read(screenWakeLockProvider);
    final checkpointStore = ref.read(wizardInstallCheckpointStoreProvider);
    StreamSubscription<InstallEvent>? logSubscription;
    InstanceRepository? repo;
    InstallTask? activeTask;
    var checkpointAvailable = false;

    state = state.copyWith(
      step: WizardStep.install,
      taskStatus: initialStatuses,
      taskProgress: 0,
      logs: resume
          ? <String>[
              ...previousLogs,
              restart ? '[info] 使用已确认配置重新执行全部安装任务…' : '[info] 从加密断点继续安装…',
              '[info] 实例目录：$installDir',
            ]
          : <String>[
              '[info] 准备安装环境…',
              '[info] 实例目录：$installDir',
            ],
      errorMessage: null,
      installFinished: false,
      installStarted: true,
      installRunning: true,
      resumeAvailable: false,
      requiresReconfiguration: false,
      instanceId: instanceId,
      installDir: installDir,
    );
    appLogger.i(
      'wizard: startInstall resume=$resume restart=$restart '
      'instanceId=$instanceId',
    );

    try {
      await wakeLock.acquire();
      await checkpointStore.write(
        _checkpoint(instanceId, installDir, installDraft),
      );
      checkpointAvailable = true;

      final resolvedRepo = await ref.read(instanceRepositoryProvider.future);
      repo = resolvedRepo;
      await resolvedRepo.upsert(
        _buildInstance(
          draft: installDraft,
          instanceId: instanceId,
          installDir: installDir,
          installStatus: InstanceInstallStatus.installing,
        ),
      );
      ref.invalidate(instancesProvider);

      final perTaskLogs = <String, List<String>>{};
      logSubscription = runtime.installEvents().listen((event) {
        perTaskLogs.putIfAbsent(event.task, () => <String>[]).add(event.line);
        _appendLog(event.line);
      });

      for (final task in InstallTask.values) {
        if (state.taskStatus[task] == InstallTaskStatus.success ||
            state.taskStatus[task] == InstallTaskStatus.skipped) {
          _appendLog('[resume] ${task.label} 已完成，继续下一项');
          continue;
        }
        activeTask = task;
        if (_shouldSkipTask(task, installDraft)) {
          _markStatus(task, InstallTaskStatus.skipped);
          _appendLog('[skip] ${task.label} 已关闭，跳过');
          await checkpointStore.write(
            _checkpoint(instanceId, installDir, installDraft),
          );
          checkpointAvailable = true;
          activeTask = null;
          continue;
        }

        _markStatus(task, InstallTaskStatus.running);
        _appendLog('[run] ${task.label}…');
        final nativeTask = _nativeTaskName(task);
        appLogger.i(
          'wizard: run task=${task.name} native=$nativeTask',
        );
        if (nativeTask != null) {
          state = state.copyWith(taskProgress: 0.35);
          final result = await runtime.runInstallTask(
            nativeTask,
            args: _runtimeArgs(installDraft, instanceId, installDir),
          );
          final streamed = perTaskLogs[nativeTask] ?? const <String>[];
          if (streamed.isEmpty) _appendLogs(result.logs);
          if (!result.success) {
            _markStatus(task, InstallTaskStatus.failed);
            final message = result.error ?? '${task.label} 执行失败';
            await checkpointStore.write(
              _checkpoint(instanceId, installDir, installDraft),
            );
            checkpointAvailable = true;
            await _persistInstallFailure(
              repo: repo,
              draft: installDraft,
              instanceId: instanceId,
              installDir: installDir,
              task: task,
              message: message,
            );
            state = state.copyWith(
              errorMessage: message,
              taskProgress: 0,
              resumeAvailable: true,
            );
            _appendLog('[error] $message');
            return;
          }
          state = state.copyWith(taskProgress: 1);
        }

        if (task == InstallTask.registerInstance) {
          await repo.upsert(
            _buildInstance(
              draft: installDraft,
              instanceId: instanceId,
              installDir: installDir,
              installStatus: InstanceInstallStatus.installed,
            ),
          );
          ref.invalidate(instancesProvider);
          if (installDraft.installWebui &&
              installDraft.webuiApiKey.isNotEmpty) {
            await WebuiKeyStore.set(instanceId, installDraft.webuiApiKey);
          }
          _appendLog('[ok] 实例已注册到本地');
        }

        _markStatus(task, InstallTaskStatus.success);
        state = state.copyWith(taskProgress: 0);
        _appendLog('[ok] ${task.label} 完成');
        await checkpointStore.write(
          _checkpoint(instanceId, installDir, installDraft),
        );
        checkpointAvailable = true;
        activeTask = null;
      }

      try {
        await checkpointStore.delete(instanceId);
      } on Object catch (error, stack) {
        appLogger.e(
          'wizard: failed to delete completed checkpoint',
          error: error,
          stackTrace: stack,
        );
        _appendLog('[warn] 安装已完成，但旧断点清理失败。');
      }
      state = state.copyWith(
        installFinished: true,
        resumeAvailable: false,
      );
      _appendLog('[done] 安装全部完成');
      appLogger.i('wizard: install finished instanceId=$instanceId');
    } on Object catch (error, stack) {
      appLogger.e('wizard: install exception', error: error, stackTrace: stack);
      final runningTask = activeTask ?? state.currentTask;
      if (runningTask != null) {
        _markStatus(runningTask, InstallTaskStatus.failed);
      }
      final message = _formatError(error);
      if (runningTask != null) {
        try {
          await checkpointStore.write(
            _checkpoint(instanceId, installDir, installDraft),
          );
          checkpointAvailable = true;
        } on Object catch (checkpointError, checkpointStack) {
          appLogger.e(
            'wizard: failed to persist checkpoint after exception',
            error: checkpointError,
            stackTrace: checkpointStack,
          );
        }
        try {
          await _persistInstallFailure(
            repo: repo,
            draft: installDraft,
            instanceId: instanceId,
            installDir: installDir,
            task: runningTask,
            message: message,
          );
        } on Object catch (persistError, persistStack) {
          appLogger.e(
            'wizard: failed to persist installation failure',
            error: persistError,
            stackTrace: persistStack,
          );
        }
      }
      state = state.copyWith(
        errorMessage: message,
        taskProgress: 0,
        resumeAvailable: checkpointAvailable,
      );
      _appendLog('[error] $message');
      _appendLog('[trace] $stack');
    } finally {
      try {
        await logSubscription?.cancel();
      } on Object catch (error, stack) {
        appLogger.e(
          'wizard: failed to cancel install log subscription',
          error: error,
          stackTrace: stack,
        );
      } finally {
        try {
          await wakeLock.release();
        } finally {
          _installRunning = false;
          state = state.copyWith(installRunning: false);
        }
      }
    }
  }

  WizardInstallCheckpoint _checkpoint(
    String instanceId,
    String installDir,
    InstanceDraft draft,
  ) =>
      WizardInstallCheckpoint(
        instanceId: instanceId,
        installDir: installDir,
        draft: draft,
        taskStatus: Map<InstallTask, InstallTaskStatus>.unmodifiable(
          state.taskStatus,
        ),
      );

  static Map<InstallTask, InstallTaskStatus> _pendingStatuses() =>
      <InstallTask, InstallTaskStatus>{
        for (final task in InstallTask.values) task: InstallTaskStatus.pending,
      };

  static Map<InstallTask, InstallTaskStatus> _resumeStatuses(
    Map<InstallTask, InstallTaskStatus> current,
  ) =>
      <InstallTask, InstallTaskStatus>{
        for (final task in InstallTask.values)
          task: current[task] == InstallTaskStatus.success ||
                  current[task] == InstallTaskStatus.skipped
              ? current[task]!
              : InstallTaskStatus.pending,
      };

  Instance _buildInstance({
    required InstanceDraft draft,
    required String instanceId,
    required String installDir,
    required InstanceInstallStatus installStatus,
    String? lastInstallTask,
    String? installError,
  }) =>
      Instance(
        id: instanceId,
        name: draft.name.isEmpty ? '未命名实例' : draft.name,
        botQq: draft.botQq,
        botNickname: draft.botNickname,
        ownerQq: draft.ownerQq,
        wsPort: draft.wsPort,
        channel: draft.channel,
        installNapcat: true,
        installWebui: draft.installWebui,
        installDir: installDir,
        createdAt: DateTime.now(),
        installStatus: installStatus,
        lastInstallTask: lastInstallTask,
        installError: installError,
      );

  Future<void> _persistInstallFailure({
    required InstanceRepository? repo,
    required InstanceDraft draft,
    required String instanceId,
    required String installDir,
    required InstallTask task,
    required String message,
  }) async {
    final targetRepo =
        repo ?? await ref.read(instanceRepositoryProvider.future);
    await targetRepo!.upsert(
      _buildInstance(
        draft: draft,
        instanceId: instanceId,
        installDir: installDir,
        installStatus: InstanceInstallStatus.failed,
        lastInstallTask: task.name,
        installError: message,
      ),
    );
    ref.invalidate(instancesProvider);
  }

  String _formatError(Object error) {
    if (error is PlatformException) {
      final message = error.message ?? '';
      return message.isEmpty
          ? '原生错误 (${error.code})'
          : '$message (${error.code})';
    }
    return error.toString();
  }

  String? _nativeTaskName(InstallTask task) => switch (task) {
        InstallTask.cloneRepo => 'cloneRepo',
        InstallTask.syncDeps => 'syncDeps',
        InstallTask.genConfig => 'genConfig',
        InstallTask.writeCore => 'writeCore',
        InstallTask.writeModel => 'writeModel',
        InstallTask.writeAdapter => 'writeAdapter',
        InstallTask.installWebui => 'installWebui',
        InstallTask.writeNapcatConfig => 'writeNapcatConfig',
        InstallTask.registerInstance => null,
      };

  bool _shouldSkipTask(InstallTask task, InstanceDraft draft) => switch (task) {
        InstallTask.installWebui => !draft.installWebui,
        _ => false,
      };

  Map<String, String> _runtimeArgs(
    InstanceDraft draft,
    String instanceId,
    String installDir,
  ) =>
      <String, String>{
        'instanceId': instanceId,
        'installDir': installDir,
        'repoPath': '$installDir/Neo-MoFox',
        'repoUrl': wizardMirrorSourceFor(draft.mirrorId).repoUrl,
        'name': draft.name,
        'botQq': draft.botQq,
        'botNickname': draft.botNickname,
        'ownerQq': draft.ownerQq,
        'apiKey': draft.apiKey,
        'wsPort': draft.wsPort.toString(),
        'channel': draft.channel,
        'webuiApiKey': draft.webuiApiKey,
        'webuiHost': '127.0.0.1',
        'webuiPort': '8000',
        'mirrorId': draft.mirrorId,
        'installNapcat': true.toString(),
        'installWebui': draft.installWebui.toString(),
      };

  void _markStatus(InstallTask task, InstallTaskStatus status) {
    final next = <InstallTask, InstallTaskStatus>{...state.taskStatus};
    next[task] = status;
    state = state.copyWith(taskStatus: next);
  }

  void _appendLog(String line) {
    final next = <String>[...state.logs, _trimWizardLogLine(line)];
    state = state.copyWith(logs: _tailWizardLogs(next));
  }

  void _appendLogs(List<String> lines) {
    if (lines.isEmpty) return;
    final next = <String>[
      ...state.logs,
      for (final line in lines) _trimWizardLogLine(line),
    ];
    state = state.copyWith(logs: _tailWizardLogs(next));
  }
}

List<String> _tailWizardLogs(List<String> logs) {
  final start =
      logs.length > _maxWizardLogLines ? logs.length - _maxWizardLogLines : 0;
  return logs.sublist(start);
}

String _trimWizardLogLine(String line) {
  if (line.length <= _maxWizardLogLineChars) return line;
  return '${line.substring(0, _maxWizardLogLineChars)}…';
}

const int _maxWizardLogLines = 300;
const int _maxWizardLogLineChars = 600;

final wizardProvider =
    NotifierProvider<WizardNotifier, WizardState>(WizardNotifier.new);

/// 用于向导名称校验的已有实例名称。
///
/// 续装时当前实例本身必须排除，否则用户保留原名称也会被误判为重复。
final wizardExistingInstanceNamesProvider =
    Provider<AsyncValue<List<String>>>((ref) {
  final currentInstanceId = ref.watch(
    wizardProvider.select((state) => state.instanceId),
  );
  return ref.watch(instancesProvider).whenData(
        (instances) => List<String>.unmodifiable(
          instances
              .where((instance) => instance.id != currentInstanceId)
              .map((instance) => instance.name),
        ),
      );
});
