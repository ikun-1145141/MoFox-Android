import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ansi_color_text.dart';
import '../../application/oobe_flow_notifier.dart';
import '../../domain/oobe_step.dart';

/// OOBE 第 3 步：解压 Debian rootfs + 装 apt 依赖，可选安装 NapCat。
///
/// 这两件全是全局一次性的（不属于单个 bot 实例），所以放在 OOBE 而不是 Wizard。
/// 先让用户确认可选组件，再由页面底部主按钮开始执行。
class ExtractRuntimeStep extends ConsumerStatefulWidget {
  const ExtractRuntimeStep({super.key});

  @override
  ConsumerState<ExtractRuntimeStep> createState() => _ExtractRuntimeStepState();
}

class _ExtractRuntimeStepState extends ConsumerState<ExtractRuntimeStep> {
  final ScrollController _logsScroll = ScrollController();
  int _lastLogCount = 0;

  @override
  void dispose() {
    _logsScroll.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom({required bool reduceMotion}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logsScroll.hasClients) return;
      if (reduceMotion) {
        _logsScroll.jumpTo(_logsScroll.position.maxScrollExtent);
        return;
      }
      _logsScroll.animateTo(
        _logsScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final flow = ref.watch(oobeFlowProvider);
    final notifier = ref.read(oobeFlowProvider.notifier);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (flow.logs.length != _lastLogCount) {
      _lastLogCount = flow.logs.length;
      _scheduleScrollToBottom(reduceMotion: reduceMotion);
    }

    final result = flow.result;
    final isRunning = result is OobeStepRunning;
    final failure = result is OobeStepFailure ? result : null;
    final canConfigure = result is OobeStepPending || failure != null;

    final statusLabel = switch (result) {
      OobeStepRunning(:final message) => message,
      OobeStepSuccess() =>
        flow.installNapcat ? '基础环境和 NapCat 已就绪' : '基础运行环境已就绪',
      OobeStepFailure(:final message) => message,
      OobeStepPending() => '等待开始…',
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.archive_outlined,
              size: 44,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isRunning ? '正在准备运行环境' : '准备运行环境',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Debian 13 和基础依赖为必需组件；NapCat 仅用于 QQ / OneBot 接入，可按需安装。',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SwitchListTile.adaptive(
            key: const ValueKey<String>('oobe-install-napcat-switch'),
            value: flow.installNapcat,
            onChanged: canConfigure ? notifier.setInstallNapcat : null,
            secondary: const Icon(Icons.extension_outlined),
            title: const Text('安装 NapCat（可选）'),
            subtitle: Text(
              flow.installNapcat
                  ? '将安装全局 NapCat，用于 QQ 登录和 OneBot v11 接入。'
                  : '暂不安装；不影响完成初始化，首次启动 NapCat 时会再安装。',
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            tileColor: scheme.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
          ),
          const SizedBox(height: 12),
          // 状态卡片
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (isRunning)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (result is OobeStepSuccess)
                      Icon(Icons.check_circle, color: scheme.primary, size: 20)
                    else if (failure != null)
                      Icon(Icons.error_outline, color: scheme.error, size: 20)
                    else
                      Icon(
                        Icons.hourglass_empty,
                        color: scheme.onSurfaceVariant,
                        size: 20,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              failure != null ? scheme.error : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isRunning) ...<Widget>[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 日志面板
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(12),
            child: Scrollbar(
              controller: _logsScroll,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _logsScroll,
                itemCount: flow.logs.isEmpty ? 1 : flow.logs.length,
                itemBuilder: (context, index) {
                  if (flow.logs.isEmpty) {
                    return Text(
                      '（暂无日志）',
                      style: _logTextStyle(scheme),
                    );
                  }
                  return AnsiColorText(
                    flow.logs[index],
                    style: _logTextStyle(scheme),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _logTextStyle(ColorScheme scheme) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.4,
      color: scheme.onSurface,
    );
  }
}
