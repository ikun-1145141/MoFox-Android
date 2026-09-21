import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../instance/domain/instance.dart';
import '../application/wizard_network_checks.dart';
import '../application/wizard_notifier.dart';
import '../domain/wizard_step.dart';
import '../domain/wizard_validation.dart';
import 'widgets/account_step.dart';
import 'widgets/eula_step.dart';
import 'widgets/install_step.dart';
import 'widgets/instance_info_step.dart';
import 'widgets/mirror_check_step.dart';
import 'widgets/model_step.dart';
import 'widgets/network_step.dart';
import 'widgets/summary_step.dart';

/// Wizard 全屏容器页。
///
/// 顶部：进度条 + 标题 + 关闭按钮
/// 中间：当前步骤的表单
/// 底部：上一步 / 下一步（最后一步在 install 内部自管）
class WizardPage extends ConsumerStatefulWidget {
  const WizardPage({this.resumeInstance, super.key});

  final Instance? resumeInstance;

  @override
  ConsumerState<WizardPage> createState() => _WizardPageState();
}

class _WizardPageState extends ConsumerState<WizardPage> {
  @override
  void initState() {
    super.initState();
    final instance = widget.resumeInstance;
    // 不能在 widget 生命周期内直接修改 provider，用 microtask 延迟到
    // 当前 build 帧结束后执行，避免 Riverpod 抛 "tried to modify a
    // provider in a widget life-cycle" 错误。
    Future.microtask(() {
      if (!mounted) return;
      if (instance != null) {
        ref.read(wizardProvider.notifier).prepareResume(instance);
      } else {
        ref.read(wizardProvider.notifier).resetForNewInstance();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(wizardProvider);
    final isInstall = state.step == WizardStep.install;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.installRunning) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('安装任务正在执行，完成或失败后才能退出。')),
          );
          return;
        }
        _confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: <Widget>[
                  // 顶栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: state.installRunning
                              ? null
                              : () => _confirmExit(context),
                          icon: const Icon(Icons.close),
                          tooltip: '退出向导',
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                state.step.title,
                                style: text.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                              ),
                              Text(
                                '第 ${state.step.index + 1} 步 / 共 ${WizardStep.values.length} 步',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 进度条
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value:
                            (state.step.index + 1) / WizardStep.values.length,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 步骤描述
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.step.description,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  if (state.requiresReconfiguration)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '没有找到完整且安全的安装断点。敏感字段已清空，请重新确认全部配置后再安装。',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  // 内容
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey<WizardStep>(state.step),
                        child: _stepBody(state.step),
                      ),
                    ),
                  ),
                  // 底部按钮：install 步骤自己管
                  if (!isInstall) _NavButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(WizardStep step) {
    return switch (step) {
      WizardStep.eula => const EulaStep(),
      WizardStep.mirrorCheck => const MirrorCheckStep(),
      WizardStep.instanceInfo => const InstanceInfoStep(),
      WizardStep.account => const AccountStep(),
      WizardStep.model => const ModelStep(),
      WizardStep.network => const NetworkStep(),
      WizardStep.summary => const SummaryStep(),
      WizardStep.install => const InstallStep(),
    };
  }

  Future<void> _confirmExit(BuildContext context) async {
    if (ref.read(wizardProvider).installRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('安装任务正在执行，完成或失败后才能退出。')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出向导？'),
        content: const Text('当前填写的内容将不会保留。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续填写'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if ((ok ?? false) && context.mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoute.dashboard);
      }
    }
  }
}

class _NavButtons extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wizardProvider.notifier);
    final state = ref.watch(wizardProvider);
    final isFirst = state.step.prev() == null;
    final isLastConfig = state.step == WizardStep.summary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: <Widget>[
            if (!isFirst)
              OutlinedButton(
                onPressed: notifier.prevStep,
                child: const Text('上一步'),
              ),
            if (!isFirst) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _canProceed(ref, state)
                    ? () {
                        if (isLastConfig) {
                          notifier.nextStep();
                          // 恢复入口没有断点时会保留原实例 ID，但必须全量重装。
                          // ignore: discarded_futures
                          notifier.startInstall(
                            resume: state.instanceId != null,
                            restart: state.requiresReconfiguration,
                          );
                        } else {
                          notifier.nextStep();
                        }
                      }
                    : null,
                child: Text(isLastConfig ? '开始安装' : '下一步'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed(WidgetRef ref, WizardState s) {
    if (s.resumeLoading || s.installRunning) return false;
    switch (s.step) {
      case WizardStep.eula:
        final document = ref.watch(eulaDocumentProvider(s.draft.mirrorId));
        return s.draft.eulaAccepted &&
            document.hasValue &&
            !document.isLoading &&
            !document.hasError;
      case WizardStep.mirrorCheck:
        final check = ref.watch(mirrorCheckProvider);
        return check.completed && check.isReachable(s.draft.mirrorId);
      case WizardStep.instanceInfo:
        return _instanceNameIsValid(ref, s);
      case WizardStep.account:
        return WizardValidation.qq(s.draft.botQq, label: 'Bot QQ') == null &&
            WizardValidation.qq(s.draft.ownerQq, label: '主人 QQ') == null;
      case WizardStep.model:
        return WizardValidation.apiKey(s.draft.apiKey) == null;
      case WizardStep.network:
        return WizardValidation.port(s.draft.wsPort) == null &&
            WizardValidation.webuiKey(
                  s.draft.webuiApiKey,
                  enabled: s.draft.installWebui,
                ) ==
                null;
      case WizardStep.summary:
        final names = _loadedExistingNames(ref);
        return s.draft.eulaAccepted &&
            names != null &&
            WizardValidation.draftIsValid(
              s.draft,
              existingNames: names,
            );
      case WizardStep.install:
        return false;
    }
  }

  bool _instanceNameIsValid(WidgetRef ref, WizardState state) {
    final names = _loadedExistingNames(ref);
    return names != null &&
        WizardValidation.instanceName(
              state.draft.name,
              existingNames: names,
            ) ==
            null;
  }

  List<String>? _loadedExistingNames(WidgetRef ref) {
    final names = ref.watch(wizardExistingInstanceNamesProvider);
    if (names.isLoading || names.hasError || !names.hasValue) return null;
    return names.value;
  }
}
