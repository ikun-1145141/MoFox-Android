import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../application/oobe_flow_notifier.dart';
import '../application/oobe_status_provider.dart';
import '../application/system_check_provider.dart';
import '../domain/oobe_step.dart';
import 'widgets/extract_runtime_step.dart';
import 'widgets/keepalive_step.dart';
import 'widgets/system_check_step.dart';
import 'widgets/welcome_step.dart';

/// OOBE 一次性引导：欢迎 → 体检 → 运行环境 → 保活 → 完成。
class OobePage extends ConsumerWidget {
  const OobePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(oobeFlowProvider);
    final notifier = ref.read(oobeFlowProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final systemCheck = ref.watch(systemCheckProvider);

    final totalSteps = OobeStep.values.length - 1;
    final currentIndex = OobeStep.values.indexOf(flow.current);
    final progress = (currentIndex + 1) / totalSteps;
    final isFirst = flow.current == OobeStep.welcome;
    final isLast = flow.current == OobeStep.done;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final canGoBack =
        !isFirst && !isLast && flow.current != OobeStep.extractRuntime;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            isLast ? '全部完成' : '第 ${currentIndex + 1} 步',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Text(
                            '共 $totalSteps 步',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0, 1),
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child:
                          _stepBody(flow.current, key: ValueKey(flow.current)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Row(
                    children: <Widget>[
                      if (canGoBack)
                        OutlinedButton(
                          onPressed: () => notifier.jumpTo(
                            OobeStep.values[currentIndex - 1],
                          ),
                          child: const Text('上一步'),
                        ),
                      if (canGoBack) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _canUsePrimaryAction(
                            flow.current,
                            flow.result,
                            systemCheck,
                          )
                              ? () async {
                                  if (isLast) {
                                    await markOobeDone(ref);
                                    if (context.mounted) {
                                      context.go(AppRoute.shell);
                                    }
                                    return;
                                  }
                                  if (flow.current == OobeStep.extractRuntime &&
                                      flow.result is! OobeStepSuccess) {
                                    await notifier.runRuntimeInstall();
                                    return;
                                  }
                                  notifier.completeStep();
                                }
                              : null,
                          child: Text(
                            _primaryLabel(flow.current, flow.result),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(OobeStep step, {Key? key}) {
    return KeyedSubtree(
      key: key,
      child: switch (step) {
        OobeStep.welcome => const WelcomeStep(),
        OobeStep.systemCheck => const SystemCheckStep(),
        OobeStep.extractRuntime => const ExtractRuntimeStep(),
        OobeStep.keepalivePerm => const KeepaliveStep(),
        OobeStep.done => const _DoneCard(),
      },
    );
  }

  String _primaryLabel(OobeStep step, OobeStepResult result) => switch (step) {
        OobeStep.welcome => '同意并继续',
        OobeStep.extractRuntime => switch (result) {
            OobeStepPending() => '开始准备',
            OobeStepRunning() => '正在准备…',
            OobeStepFailure() => '重试',
            OobeStepSuccess() => '继续',
          },
        OobeStep.done => '开始使用',
        _ => '下一步',
      };

  /// 运行环境页的主按钮兼任“开始 / 重试 / 继续”；执行中不可重复触发。
  bool _canUsePrimaryAction(
    OobeStep step,
    OobeStepResult result,
    SystemCheckState systemCheck,
  ) {
    if (step == OobeStep.systemCheck) return systemCheck.allPassed;
    if (step != OobeStep.extractRuntime) return true;
    return result is! OobeStepRunning &&
        (result is! OobeStepFailure || result.recoverable);
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 56,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '一切就绪',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '点击下方按钮进入主界面，创建你的第一个 Bot 实例。',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
