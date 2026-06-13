import 'dart:async';

import 'package:flutter/services.dart';
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
    this.installStarted = false,
    this.resumeAvailable = false,
    this.instanceId,
    this.installDir,
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

  /// 安装流程是否已经启动过。
  final bool installStarted;

  /// 是否允许从失败任务继续安装。
  final bool resumeAvailable;

  /// 当前安装实例 ID。
  final String? instanceId;

  /// 当前安装目录。
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
    bool? resumeAvailable,
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
        resumeAvailable: resumeAvailable ?? this.resumeAvailable,
        instanceId: identical(instanceId, _sentinel)
            ? this.instanceId
            : instanceId as String?,
        installDir: identical(installDir, _sentinel)
            ? this.installDir
            : installDir as String?,
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
  bool _installRunning = false;

  @override
  WizardState build() {
    ref.onDispose(() => _runner?.cancel());
    return WizardState(
      step: WizardStep.eula,
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

  void prepareResume(Instance instance) {
    state = state.copyWith(
      step: WizardStep.install,
      draft: state.draft.copyWith(
        name: instance.name,
        botQq: instance.botQq,
        botNickname: instance.botNickname,
        ownerQq: instance.ownerQq,
        wsPort: instance.wsPort,
        channel: instance.channel,
        installWebui: instance.installWebui,
      ),
      taskStatus: <InstallTask, InstallTaskStatus>{
        for (final task in InstallTask.values) task: InstallTaskStatus.pending,
      },
      taskProgress: 0,
      logs: <String>[
        '[info] 已载入未完成实例：${instance.name}',
        '[info] 实例目录：${instance.installDir}',
        if (instance.installError != null)
          '[last-error] ${instance.installError}',
      ],
      errorMessage: instance.installError,
      napcatQrPayload: null,
      installFinished: false,
      installStarted: true,
      resumeAvailable: true,
      instanceId: instance.id,
      installDir: instance.installDir,
    );
  }

  /// 启动安装流程。原生层负责 rootfs/proot/脚本执行，Flutter 负责状态编排。
  Future<void> startInstall({bool resume = false}) async {
    if (_installRunning) return;
    _runner?.cancel();
    _installRunning = true;
    final runtime = ref.read(runtimeBridgeProvider);
    // 实例 id 在 startInstall 起手处生成一次，贯穿整个安装流程：
    //   - 所有 native task 都用它拼出 /root/instances/<id>/Neo-MoFox 这种路径
    //   - registerInstance 那步写到 SharedPreferences 用同一个 id
    // 这样 dashboard 里点"终端"按钮才能用 instance.repoPath / instance.installDir
    // 直接命中实际目录。
    final instanceId = resume && state.instanceId != null
        ? state.instanceId!
        : 'inst-${DateTime.now().millisecondsSinceEpoch}';
    final installDir = resume && state.installDir != null
        ? state.installDir!
        : '/root/instances/$instanceId';
    final repo = await ref.read(instanceRepositoryProvider.future);
    await repo.upsert(
      _buildInstance(
        instanceId: instanceId,
        installDir: installDir,
        installStatus: InstanceInstallStatus.installing,
      ),
    );
    ref.invalidate(instancesProvider);
    state = state.copyWith(
      taskStatus: resume
          ? _resumeStatuses(state.taskStatus)
          : <InstallTask, InstallTaskStatus>{
              for (final t in InstallTask.values) t: InstallTaskStatus.pending,
            },
      taskProgress: 0,
      logs: resume
          ? <String>[
              ...state.logs,
              '[info] 从上次失败处继续安装…',
              '[info] 实例目录：$installDir',
            ]
          : <String>['[info] 准备安装环境…', '[info] 实例目录：$installDir'],
      errorMessage: null,
      installFinished: false,
      installStarted: true,
      resumeAvailable: false,
      instanceId: instanceId,
      installDir: installDir,
    );

    // 整个安装流程订阅一次原生事件流，按 task 字段累积日志。
    // 这样可以避免 task 切换瞬间 sink 被 detach 导致 emit 丢日志。
    final perTaskLogs = <String, List<String>>{};
    final logSubscription = runtime.installEvents().listen((event) {
      perTaskLogs.putIfAbsent(event.task, () => <String>[]).add(event.line);
      _appendLog(event.line);
    });

    try {
      for (final task in InstallTask.values) {
        if (state.taskStatus[task] == InstallTaskStatus.success) {
          _appendLog('[resume] ${task.label} 已完成，继续下一项');
          continue;
        }
        if (_shouldSkipTask(task)) {
          _markStatus(task, InstallTaskStatus.skipped);
          _appendLog('[skip] ${task.label} 已关闭，跳过');
          continue;
        }

        _markStatus(task, InstallTaskStatus.running);
        _appendLog('[run] ${task.label}…');

        final nativeTask = _nativeTaskName(task);
        if (nativeTask != null) {
          state = state.copyWith(taskProgress: 0.35);
          final result = await runtime.runInstallTask(
            nativeTask,
            args: _runtimeArgs(instanceId, installDir),
          );
          // 流为空时（极端 race 或事件被 framework 丢弃）回退到 result.logs。
          final streamed = perTaskLogs[nativeTask] ?? const <String>[];
          if (streamed.isEmpty) {
            _appendLogs(result.logs);
          }
          if (!result.success) {
            _markStatus(task, InstallTaskStatus.failed);
            final message = result.error ?? '${task.label} 执行失败';
            await _persistInstallFailure(
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

        // 注册实例：真正写入仓库
        if (task == InstallTask.registerInstance) {
          await repo.upsert(
            _buildInstance(
              instanceId: instanceId,
              installDir: installDir,
              installStatus: InstanceInstallStatus.installed,
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
    } catch (error, stack) {
      // 任意一步抛出未处理异常（典型例子：原生侧 PlatformException——比如 bootstrap zip
      // 没打进 APK，context.assets.open 抛 FileNotFoundException）。如果不在这里 catch，
      // state 会永远停在 running + taskProgress: 0.35，UI 看上去就是"卡在 3% 不动"。
      final running = state.currentTask;
      if (running != null) {
        _markStatus(running, InstallTaskStatus.failed);
      }
      final message = _formatError(error);
      final instanceId = state.instanceId;
      final installDir = state.installDir;
      if (instanceId != null && installDir != null && running != null) {
        await _persistInstallFailure(
          instanceId: instanceId,
          installDir: installDir,
          task: running,
          message: message,
        );
      }
      state = state.copyWith(
        errorMessage: message,
        taskProgress: 0,
        resumeAvailable: true,
      );
      _appendLog('[error] $message');
      _appendLog('[trace] $stack');
    } finally {
      await logSubscription.cancel();
      _installRunning = false;
    }
  }

  Map<InstallTask, InstallTaskStatus> _resumeStatuses(
    Map<InstallTask, InstallTaskStatus> current,
  ) {
    return <InstallTask, InstallTaskStatus>{
      for (final task in InstallTask.values)
        task: current[task] == InstallTaskStatus.success
            ? InstallTaskStatus.success
            : InstallTaskStatus.pending,
    };
  }

  Instance _buildInstance({
    required String instanceId,
    required String installDir,
    required InstanceInstallStatus installStatus,
    String? lastInstallTask,
    String? installError,
  }) {
    final draft = state.draft;
    return Instance(
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
  }

  Future<void> _persistInstallFailure({
    required String instanceId,
    required String installDir,
    required InstallTask task,
    required String message,
  }) async {
    final repo = await ref.read(instanceRepositoryProvider.future);
    await repo.upsert(
      _buildInstance(
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
      final code = error.code;
      final msg = error.message ?? '';
      return msg.isEmpty ? '原生错误 ($code)' : '$msg ($code)';
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

  bool _shouldSkipTask(InstallTask task) => switch (task) {
        InstallTask.installWebui => !state.draft.installWebui,
        _ => false,
      };

  Map<String, String> _runtimeArgs(String instanceId, String installDir) {
    final draft = state.draft;
    return <String, String>{
      // 多 bot 路径：所有 per-instance 任务都用这两个键拼路径，
      // 原生侧 RuntimeScripts 默认值是 /root/Neo-MoFox（兼容 OOBE 之前的旧逻辑）。
      'instanceId': instanceId,
      'installDir': installDir,
      'repoPath': '$installDir/Neo-MoFox',
      'repoUrl': _repoUrlForMirror(draft.mirrorId),
      'name': draft.name,
      'botQq': draft.botQq,
      'botNickname': draft.botNickname,
      'ownerQq': draft.ownerQq,
      'apiKey': draft.apiKey,
      'apiBaseUrl': draft.apiBaseUrl,
      'wsPort': draft.wsPort.toString(),
      'channel': draft.channel,
      'webuiApiKey': draft.webuiApiKey,
      'mirrorId': draft.mirrorId,
      'installNapcat': true.toString(),
      'installWebui': draft.installWebui.toString(),
    };
  }

  String _repoUrlForMirror(String mirrorId) => switch (mirrorId) {
        'ghproxy' =>
          'https://ghfast.top/https://github.com/MoFox-Studio/Neo-MoFox.git',
        'gitee' => 'https://gitee.com/MoFox-Studio/Neo-MoFox.git',
        _ => 'https://github.com/MoFox-Studio/Neo-MoFox.git',
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
