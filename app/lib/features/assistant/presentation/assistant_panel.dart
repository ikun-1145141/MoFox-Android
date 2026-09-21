import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mofox_android/app/router/app_router.dart';
import 'package:mofox_android/features/assistant/application/assistant_notifier.dart';
import 'package:mofox_android/features/assistant/application/assistant_policy.dart';
import 'package:mofox_android/features/assistant/application/assistant_settings_notifier.dart';
import 'package:mofox_android/features/assistant/domain/assistant_models.dart';

class AssistantPanel extends ConsumerStatefulWidget {
  const AssistantPanel({
    required this.spec,
    required this.onFillTerminal,
    required this.readTerminalSelection,
    required this.onClose,
    super.key,
  });

  final AssistantSessionSpec spec;
  final ValueChanged<String> onFillTerminal;
  final String? Function() readTerminalSelection;
  final VoidCallback onClose;

  @override
  ConsumerState<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends ConsumerState<AssistantPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  int? _lastContentRevision;
  bool _forceScrollToBottom = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final value = preset ?? _inputController.text;
    if (value.trim().isEmpty) return;
    _inputController.clear();
    _forceScrollToBottom = true;
    ref.read(assistantProvider(widget.spec).notifier).send(value);
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 72;
  }

  void _followLatestContent({required bool reduceMotion}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (reduceMotion) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _explainSelection() {
    final selection = widget.readTerminalSelection()?.trim();
    if (selection == null || selection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在终端中选择一段内容')),
      );
      return;
    }
    _send('请解释下面这段终端内容，并告诉我下一步怎么做：\n$selection');
  }

  Future<void> _diagnoseWithLogs() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送最近日志？'),
        content: const Text(
          '将截取 Bot 和 NapCat 最近各 20 行日志，经本地脱敏后发送到你配置的模型服务。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意并诊断'),
          ),
        ],
      ),
    );
    if (allowed ?? false) {
      _forceScrollToBottom = true;
      await ref
          .read(assistantProvider(widget.spec).notifier)
          .sendWithRecentLogs('请结合最近日志诊断 Bot 为什么没有回复。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantProvider(widget.spec));
    final notifier = ref.read(assistantProvider(widget.spec).notifier);
    final settings = ref.watch(assistantSettingsProvider).valueOrNull;
    final yoloEnabled = settings?.yoloEnabled ?? false;
    final configured = settings?.configured ?? false;
    final contentRevision = Object.hash(
      state.messages.length,
      state.streamedText.length,
      state.executionOutput?.length,
      state.pendingAction,
      state.errorMessage,
      state.phase,
    );
    if (_lastContentRevision != contentRevision) {
      final shouldFollow = _lastContentRevision == null ||
          _forceScrollToBottom ||
          _isNearBottom();
      _lastContentRevision = contentRevision;
      _forceScrollToBottom = false;
      if (shouldFollow) {
        _followLatestContent(
          reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
        );
      }
    }
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
          Container(
            color: yoloEnabled
                ? scheme.errorContainer
                : scheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: <Widget>[
                Icon(
                  yoloEnabled ? Icons.bolt : Icons.auto_awesome,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    yoloEnabled ? 'AI 运维助手 · YOLO 已开启' : 'AI 运维助手 · 副驾驶',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (yoloEnabled)
                  TextButton.icon(
                    onPressed: notifier.stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('急停'),
                  ),
                IconButton(
                  tooltip: '清空对话',
                  onPressed: notifier.clearConversation,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: '关闭助手',
                  onPressed: () {
                    notifier.stop();
                    widget.onClose();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (!configured)
            MaterialBanner(
              content: Text(
                settings != null &&
                        !settings.enabled &&
                        settings.baseUrl.isNotEmpty &&
                        settings.model.isNotEmpty &&
                        settings.hasApiKey
                    ? 'AI 助手已经配置，但尚未启用。'
                    : 'AI 助手配置不完整，终端本身仍可正常使用。',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => context.push(AppRoute.assistantSettings),
                  child: const Text('去配置'),
                ),
              ],
            ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                if (state.messages.isEmpty) ...<Widget>[
                  Text(
                    '你想维护什么？',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      ActionChip(
                        label: const Text('Bot 为什么没回复？'),
                        onPressed: _diagnoseWithLogs,
                      ),
                      ActionChip(
                        label: const Text('检查运行状态'),
                        onPressed: () => _send('检查 Bot 和 NapCat 是否正常运行。'),
                      ),
                      ActionChip(
                        label: const Text('检查存储'),
                        onPressed: () => _send('检查手机存储空间是否够用。'),
                      ),
                      ActionChip(
                        label: const Text('解释选中内容'),
                        onPressed: _explainSelection,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                for (var index = 0; index < state.messages.length; index++)
                  if (state.messages[index].role != AssistantRole.system)
                    AssistantMessageBubble(
                      message: state.messages[index],
                      onRetry: state.isBusy
                          ? null
                          : () {
                              _forceScrollToBottom = true;
                              notifier.retryMessage(index);
                            },
                    ),
                if (state.streamedText.isNotEmpty)
                  AssistantMessageBubble(
                    message: AssistantMessage(
                      role: AssistantRole.assistant,
                      text: state.streamedText,
                    ),
                  ),
                if (state.phase == AssistantPhase.executing ||
                    state.executionOutput != null)
                  AssistantExecutionCard(
                    running: state.phase == AssistantPhase.executing,
                    output: state.executionOutput,
                  ),
                if (state.pendingAction != null)
                  _ActionCard(
                    action: state.pendingAction!,
                    policy: state.policyResult,
                    canFill: notifier.canFillPending(),
                    onFill: () {
                      widget.onFillTerminal(state.pendingAction!.command!);
                      notifier.rejectPending();
                    },
                    onExecute: notifier.executePending,
                    onReject: notifier.rejectPending,
                  ),
                if (state.errorMessage != null)
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(state.errorMessage!),
                    ),
                  ),
              ],
            ),
          ),
          if (state.isBusy)
            LinearProgressIndicator(
              color: yoloEnabled ? scheme.error : null,
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !state.isBusy && configured,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '说说你想完成什么……',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: state.isBusy ? '停止' : '发送',
                    onPressed: state.isBusy ? notifier.stop : _send,
                    icon: Icon(state.isBusy ? Icons.stop : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantMessageBubble extends StatefulWidget {
  const AssistantMessageBubble({
    required this.message,
    this.onRetry,
    super.key,
  });

  final AssistantMessage message;
  final VoidCallback? onRetry;

  @override
  State<AssistantMessageBubble> createState() => _AssistantMessageBubbleState();
}

class _AssistantMessageBubbleState extends State<AssistantMessageBubble> {
  final _selectionKey = GlobalKey<SelectionAreaState>();

  void _selectAll() {
    _selectionKey.currentState?.selectableRegion
        .selectAll(SelectionChangedCause.toolbar);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.message.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息已复制')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.message.role == AssistantRole.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: user ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectionArea(
              key: _selectionKey,
              child: Text(widget.message.text),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _selectAll,
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('选择'),
                  style: _messageActionStyle,
                ),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('复制'),
                  style: _messageActionStyle,
                ),
                TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                  style: _messageActionStyle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final ButtonStyle _messageActionStyle = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  minimumSize: const Size(64, 48),
  tapTargetSize: MaterialTapTargetSize.padded,
);

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.action,
    required this.policy,
    required this.canFill,
    required this.onFill,
    required this.onExecute,
    required this.onReject,
  });

  final AssistantAction action;
  final AssistantPolicyResult? policy;
  final bool canFill;
  final VoidCallback onFill;
  final VoidCallback onExecute;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final executable = policy?.decision == AssistantPolicyDecision.allow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(action.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(action.reason),
            if (action.command != null) ...<Widget>[
              const SizedBox(height: 8),
              SelectableText(
                r'$ ' + action.command!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
            if (policy != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                policy!.reason,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: <Widget>[
                TextButton(onPressed: onReject, child: const Text('取消')),
                if (action.command != null)
                  TextButton(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: action.command!),
                    ),
                    child: const Text('复制'),
                  ),
                if (action.command != null && canFill)
                  OutlinedButton(
                    onPressed: onFill,
                    child: const Text('填入终端'),
                  ),
                if (executable)
                  FilledButton(
                    onPressed: onExecute,
                    child: const Text('确认执行'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AssistantExecutionCard extends StatefulWidget {
  const AssistantExecutionCard({
    required this.running,
    this.output,
    super.key,
  });

  final bool running;
  final String? output;

  @override
  State<AssistantExecutionCard> createState() => _AssistantExecutionCardState();
}

class _AssistantExecutionCardState extends State<AssistantExecutionCard> {
  late bool _expanded = widget.running;

  @override
  void didUpdateWidget(covariant AssistantExecutionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running && !widget.running) _expanded = false;
    if (!oldWidget.running && widget.running) _expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(widget.running ? '正在执行命令…' : '执行结果'),
                ),
                TextButton.icon(
                  onPressed: widget.running
                      ? null
                      : () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(_expanded ? '收起' : '展开'),
                ),
              ],
            ),
            if (widget.running) const LinearProgressIndicator(),
            if (_expanded && widget.output != null) ...<Widget>[
              const SizedBox(height: 6),
              SelectionArea(
                child: Text(
                  widget.output!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: widget.output!),
                  ),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制结果'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
