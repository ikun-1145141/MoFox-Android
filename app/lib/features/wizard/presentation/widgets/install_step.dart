import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_router.dart';
import '../../application/wizard_notifier.dart';
import '../../domain/wizard_step.dart';
import 'napcat_qr_sheet.dart';

class InstallStep extends ConsumerStatefulWidget {
  const InstallStep({super.key});

  @override
  ConsumerState<InstallStep> createState() => _InstallStepState();
}

class _InstallStepState extends ConsumerState<InstallStep> {
  bool _qrShown = false;
  bool _logsExpanded = false;
  final ScrollController _logsScroll = ScrollController();

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
    final state = ref.watch(wizardProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // QR 弹窗：napcatQrPayload 出现时弹出，消失时关闭
    ref.listen<WizardState>(wizardProvider, (prev, next) {
      if (next.napcatQrPayload != null && !_qrShown) {
        _qrShown = true;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => NapcatQrSheet(payload: next.napcatQrPayload!),
        ).whenComplete(() => _qrShown = false);
      } else if (next.napcatQrPayload == null && _qrShown) {
        Navigator.of(context).pop();
        _qrShown = false;
      }
      if ((prev?.logs.length ?? 0) != next.logs.length && _logsExpanded) {
        _scheduleScrollToBottom();
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: <Widget>[
          // 当前任务卡片
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (state.errorMessage != null)
                      Icon(Icons.error_outline, color: scheme.error, size: 20)
                    else if (!state.installFinished)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.check_circle, color: scheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.errorMessage != null
                            ? '安装中断'
                            : state.installFinished
                                ? '安装完成'
                                : (state.currentTask?.label ?? '准备中…'),
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${(state.overallProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: text.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: state.installFinished ? 1 : state.overallProgress,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                ),
                if (state.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
                  if (state.resumeAvailable) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '可保留已完成任务，从失败处继续安装。',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 任务列表
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  for (final task in InstallTask.values)
                    _TaskRow(
                      task: task,
                      status:
                          state.taskStatus[task] ?? InstallTaskStatus.pending,
                    ),
                  const SizedBox(height: 8),
                  // 日志折叠
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionPanelList(
                        elevation: 0,
                        expandedHeaderPadding: EdgeInsets.zero,
                        expansionCallback: (_, __) {
                          setState(() => _logsExpanded = !_logsExpanded);
                          if (_logsExpanded) _scheduleScrollToBottom();
                        },
                        children: <ExpansionPanel>[
                          ExpansionPanel(
                            backgroundColor: scheme.surfaceContainerLow,
                            isExpanded: _logsExpanded,
                            headerBuilder: (_, __) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.terminal),
                              title: Text(
                                '安装日志（${state.logs.length}）',
                                style: text.titleSmall,
                              ),
                            ),
                            body: Container(
                              width: double.infinity,
                              height: 260,
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Scrollbar(
                                controller: _logsScroll,
                                thumbVisibility: true,
                                child: state.logs.isEmpty
                                    ? const Align(
                                        alignment: Alignment.topLeft,
                                        child: Text(
                                          '（暂无日志）',
                                          style: _logTextStyle,
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _logsScroll,
                                        itemCount: state.logs.length,
                                        itemBuilder: (context, index) => Text(
                                          state.logs[index],
                                          style: _logTextStyle,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 完成时显示进入按钮，失败时显示续装按钮
          if (state.installFinished)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go(AppRoute.dashboard),
                icon: const Icon(Icons.check),
                label: const Text('完成，返回主界面'),
              ),
            )
          else if (state.resumeAvailable)
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => ref
                        .read(wizardProvider.notifier)
                        .startInstall(resume: true),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('从断点继续安装'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => ref.read(wizardProvider.notifier).startInstall(),
                  child: const Text('重新安装'),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                child: Text(
                  '安装中，请勿关闭页面',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const TextStyle _logTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 12,
  height: 1.4,
);

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.status});
  final InstallTask task;
  final InstallTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      InstallTaskStatus.pending => (
          Icons.radio_button_unchecked,
          scheme.outline,
        ),
      InstallTaskStatus.running => (Icons.autorenew, scheme.primary),
      InstallTaskStatus.success => (Icons.check_circle, scheme.primary),
      InstallTaskStatus.failed => (Icons.cancel, scheme.error),
      InstallTaskStatus.skipped => (Icons.remove_circle_outline, scheme.outline),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        task.label,
        style: TextStyle(
          color: status == InstallTaskStatus.pending
              ? scheme.onSurfaceVariant
              : scheme.onSurface,
        ),
      ),
      trailing: status == InstallTaskStatus.skipped
          ? Text(
              '已跳过',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )
          : null,
    );
  }
}
