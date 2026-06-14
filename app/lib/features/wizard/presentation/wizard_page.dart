import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../instance/domain/instance.dart';
import '../application/wizard_notifier.dart';
import '../domain/wizard_step.dart';
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
    if (instance != null) {
      ref.read(wizardProvider.notifier).prepareResume(instance);
    } else {
      ref.read(wizardProvider.notifier).resetForNewInstance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(wizardProvider);
    final isInstall = state.step == WizardStep.install;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              // 顶栏
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => _confirmExit(context),
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
                    value: (state.step.index + 1) / WizardStep.values.length,
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
              // 内容
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
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
                onPressed: _canProceed(state)
                    ? () {
                        if (isLastConfig) {
                          notifier
                            ..nextStep()
                            // ignore: discarded_futures
                            ..startInstall();
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

  bool _canProceed(WizardState s) {
    switch (s.step) {
      case WizardStep.eula:
        return s.draft.eulaAccepted;
      case WizardStep.mirrorCheck:
        return s.draft.mirrorId.trim().isNotEmpty;
      case WizardStep.instanceInfo:
        return s.draft.name.trim().isNotEmpty;
      case WizardStep.account:
        return s.draft.botQq.trim().isNotEmpty &&
            s.draft.ownerQq.trim().isNotEmpty;
      case WizardStep.model:
        return s.draft.apiBaseUrl.trim().isNotEmpty;
      case WizardStep.network:
        return s.draft.wsPort > 0 &&
            (!s.draft.installWebui || s.draft.webuiApiKey.trim().isNotEmpty);
      case WizardStep.summary:
        return true;
      case WizardStep.install:
        return false;
    }
  }
}
