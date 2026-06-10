import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/oobe_flow_notifier.dart';
import '../../domain/oobe_step.dart';

/// OOBE 第 3 步：解压 Debian rootfs + 装 apt 依赖。
///
/// 这两件全是全局一次性的（不属于单个 bot 实例），所以放在 OOBE 而不是 Wizard。
/// 进入这一步会自动开跑，失败可以点重试。
class ExtractRuntimeStep extends ConsumerStatefulWidget {
  const ExtractRuntimeStep({super.key});

  @override
  ConsumerState<ExtractRuntimeStep> createState() =>
      _ExtractRuntimeStepState();
}

class _ExtractRuntimeStepState extends ConsumerState<ExtractRuntimeStep> {
  final ScrollController _logsScroll = ScrollController();
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(oobeFlowProvider.notifier).runRuntimeInstall(),
    );
  }

  @override
  void dispose() {
    _logsScroll.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logsScroll.hasClients) return;
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

    if (flow.logs.length != _lastLogCount) {
      _lastLogCount = flow.logs.length;
      _scheduleScrollToBottom();
    }

    final result = flow.result;
    final isRunning = result is OobeStepRunning;
    final failure = result is OobeStepFailure ? result : null;

    final statusLabel = switch (result) {
      OobeStepRunning(:final message) => message,
      OobeStepSuccess() => '运行环境就绪',
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
            '正在准备运行环境',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '解压 Debian 13 系统、安装基础依赖。\n仅在首次启动时执行，之后所有 bot 实例共用这套环境。',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
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
                          color: failure != null
                              ? scheme.error
                              : scheme.onSurface,
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
                if (failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: notifier.runRuntimeInstall,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
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
              child: flow.logs.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '（暂无日志）',
                        style: _logTextStyle(scheme),
                      ),
                    )
                  : ListView.builder(
                      controller: _logsScroll,
                      itemCount: flow.logs.length,
                      itemBuilder: (context, index) => Text(
                        flow.logs[index],
                        style: _logTextStyle(scheme),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
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
