import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../application/oobe_flow_notifier.dart';
import '../application/oobe_status_provider.dart';
import '../domain/oobe_step.dart';
import 'widgets/napcat_qr_step.dart';

/// MD3 标准 onboarding wizard：顶部进度指示 + 卡片化步骤内容 + 底部双按钮。
class OobePage extends ConsumerWidget {
  const OobePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(oobeFlowProvider);
    final notifier = ref.read(oobeFlowProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    final totalSteps = OobeStep.values.length - 1;
    final currentIndex = OobeStep.values.indexOf(flow.current);
    final progress = (currentIndex + 1) / totalSteps;
    final isFirst = flow.current == OobeStep.welcome;
    final isLast = flow.current == OobeStep.done;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('MoFox 安装向导'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        '第 ${currentIndex + 1} 步',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        '共 $totalSteps 步',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _stepBody(flow.current, key: ValueKey(flow.current)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: <Widget>[
                  if (!isFirst && !isLast)
                    OutlinedButton(
                      onPressed: () => notifier.jumpTo(
                        OobeStep.values[currentIndex - 1],
                      ),
                      child: const Text('上一步'),
                    ),
                  if (!isFirst && !isLast) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (isLast) {
                          await markOobeDone(ref);
                          if (context.mounted) context.go(AppRoute.shell);
                          return;
                        }
                        notifier.completeStep();
                      },
                      child: Text(_primaryLabel(flow.current)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(OobeStep step, {Key? key}) {
    return switch (step) {
      OobeStep.napcatLogin => NapcatQrStep(key: key),
      OobeStep.done => _DoneCard(key: key),
      _ => _PlaceholderStep(key: key, step: step),
    };
  }

  String _primaryLabel(OobeStep step) => switch (step) {
        OobeStep.welcome => '同意并继续',
        OobeStep.done => '进入主界面',
        _ => '下一步',
      };
}

class _PlaceholderStep extends StatelessWidget {
  const _PlaceholderStep({required this.step, super.key});
  final OobeStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _stepIcon(step),
              size: 36,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            stepTitle(step),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            stepDescription(step),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            '部署完成',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '一切就绪，可以开始使用 MoFox 了。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

IconData _stepIcon(OobeStep s) => switch (s) {
      OobeStep.welcome => Icons.waving_hand_outlined,
      OobeStep.systemCheck => Icons.health_and_safety_outlined,
      OobeStep.extractRootfs => Icons.unarchive_outlined,
      OobeStep.keepalivePerm => Icons.battery_saver_outlined,
      OobeStep.installRuntimeDeps => Icons.download_outlined,
      OobeStep.napcatLogin => Icons.qr_code_2_outlined,
      OobeStep.fetchNeoMofox => Icons.cloud_download_outlined,
      OobeStep.generateConfig => Icons.settings_outlined,
      OobeStep.fillFormAndStart => Icons.edit_note_outlined,
      OobeStep.done => Icons.check_circle_outline,
    };

String stepTitle(OobeStep s) => switch (s) {
      OobeStep.welcome => '欢迎使用 MoFox',
      OobeStep.systemCheck => '系统体检',
      OobeStep.extractRootfs => '解压内嵌运行时',
      OobeStep.keepalivePerm => '配置后台保活',
      OobeStep.installRuntimeDeps => '安装运行时依赖',
      OobeStep.napcatLogin => '登录 QQ',
      OobeStep.fetchNeoMofox => '拉取 Neo-MoFox',
      OobeStep.generateConfig => '生成默认配置',
      OobeStep.fillFormAndStart => '填写信息并启动',
      OobeStep.done => '完成',
    };

String stepDescription(OobeStep s) => switch (s) {
      OobeStep.welcome => '阅读并同意用户协议，开始一键部署。',
      OobeStep.systemCheck => '检查 ABI、剩余空间与内存是否满足要求。',
      OobeStep.extractRootfs => '把内嵌的 Termux rootfs 解压到 App 私有目录。',
      OobeStep.keepalivePerm => '跳到系统设置开启自启动 / 耗电不限制 / 后台锁定。',
      OobeStep.installRuntimeDeps => '在 rootfs 中安装 python / git / uv。',
      OobeStep.napcatLogin => '安装 Napcat 并展示登录二维码，用 QQ 扫码完成登录。',
      OobeStep.fetchNeoMofox => 'git clone Neo-MoFox 并 uv sync 同步依赖。',
      OobeStep.generateConfig => '首次启动 Bot 让其写出默认 toml，然后优雅停止。',
      OobeStep.fillFormAndStart => '填写主人 QQ / 模型 API Key / 端口，写入配置后启动。',
      OobeStep.done => '一切就绪。',
    };
