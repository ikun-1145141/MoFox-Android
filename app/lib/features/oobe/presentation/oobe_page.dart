import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../application/oobe_flow_notifier.dart';
import '../application/oobe_status_provider.dart';
import '../domain/oobe_step.dart';
import 'widgets/napcat_qr_step.dart';

class OobePage extends ConsumerWidget {
  const OobePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(oobeFlowProvider);
    final notifier = ref.read(oobeFlowProvider.notifier);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BrandColors.primaryGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Header(step: flow.current),
                const SizedBox(height: 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _stepBody(flow.current, key: ValueKey(flow.current)),
                  ),
                ),
                const SizedBox(height: 16),
                _BottomBar(
                  flow: flow,
                  onPrimary: () async {
                    if (flow.current == OobeStep.done) {
                      await markOobeDone(ref);
                      if (context.mounted) context.go(AppRoute.shell);
                      return;
                    }
                    notifier.completeStep();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(OobeStep step, {Key? key}) {
    switch (step) {
      case OobeStep.napcatLogin:
        return NapcatQrStep(key: key);
      case OobeStep.done:
        return _DoneCard(key: key);
      default:
        return _PlaceholderStep(key: key, step: step);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step});
  final OobeStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'MoFox 安装向导',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '第 ${OobeStep.values.indexOf(step) + 1} 步 / 共 ${OobeStep.values.length - 1} 步',
          style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}

class _PlaceholderStep extends StatelessWidget {
  const _PlaceholderStep({super.key, required this.step});
  final OobeStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(stepTitle(step),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              stepDescription(step),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, size: 64),
            SizedBox(height: 16),
            Text('部署完成，进入主界面。'),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.flow, required this.onPrimary});
  final OobeFlowState flow;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (flow.current) {
      OobeStep.welcome => '同意并继续',
      OobeStep.done => '进入主界面',
      _ => '下一步',
    };
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: scheme.surface,
          foregroundColor: scheme.primary,
        ),
        onPressed: onPrimary,
        child: Text(label),
      ),
    );
  }
}

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
