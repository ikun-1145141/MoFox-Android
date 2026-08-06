import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/text_editor_notifier.dart';
import '../domain/rootfs_file_exception.dart';
import '../domain/rootfs_file_models.dart';
import 'widgets/markdown_view.dart';
import 'widgets/text_file_editing_controller.dart';

/// 通用文本文件编辑页。
///
/// 支持根据文件类型提供语法高亮（Python/结构化文本），Markdown 文件可切换
/// 源码/预览视图。保存使用 CAS revision 检测外部修改冲突。
class TextFileEditorPage extends ConsumerStatefulWidget {
  const TextFileEditorPage({required this.args, super.key});

  final TextFileEditorRouteArgs args;

  @override
  ConsumerState<TextFileEditorPage> createState() => _TextFileEditorPageState();
}

class _TextFileEditorPageState extends ConsumerState<TextFileEditorPage> {
  late final TextFileEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  bool _controllerSynced = false;
  bool _previewMode = false;

  @override
  void initState() {
    super.initState();
    _controller = TextFileEditingController(
      language: widget.args.language,
    );
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_controllerSynced) return;
    ref
        .read(textEditorProvider(_editorKey).notifier)
        .updateText(_controller.text);
  }

  TextEditorKey get _editorKey => TextEditorKey(
        scope: widget.args.scope,
        path: widget.args.relativePath,
      );

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(textEditorProvider(_editorKey));
    if (state.loadStatus == TextEditorLoadStatus.ready && !_controllerSynced) {
      _controllerSynced = true;
      _controller.text = state.text;
    }
    final canPreview = widget.args.language.supportsPreview;
    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscard(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _maybePopWithConfirm(context),
          ),
          title: Text(state.path.name.isEmpty
              ? widget.args.language.displayName
              : state.path.name),
          actions: [
            if (canPreview)
              IconButton(
                tooltip: _previewMode ? '编辑源码' : '预览渲染',
                onPressed: () => setState(() => _previewMode = !_previewMode),
                icon: Icon(_previewMode ? Icons.edit : Icons.visibility),
              ),
            if (state.isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: '保存',
                onPressed: state.canSave ? () => _save(context) : null,
                icon: const Icon(Icons.save),
              ),
          ],
        ),
        body: _buildBody(context, state),
        bottomNavigationBar: _buildStatusBar(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TextEditorState state) {
    switch (state.loadStatus) {
      case TextEditorLoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case TextEditorLoadStatus.notFound:
        return _StatusView(
          icon: Icons.find_in_page_outlined,
          title: '文件不存在',
          message: '该文件可能已被删除。',
          action: TextButton(
            onPressed: () => context.pop(),
            child: const Text('返回'),
          ),
        );
      case TextEditorLoadStatus.failed:
        return _StatusView(
          icon: Icons.error_outline,
          title: '加载失败',
          message: state.saveError ?? '未知错误',
          action: TextButton(
            onPressed: () =>
                ref.read(textEditorProvider(_editorKey).notifier).reload(),
            child: const Text('重试'),
          ),
        );
      case TextEditorLoadStatus.idle:
      case TextEditorLoadStatus.ready:
        if (_previewMode && widget.args.language.supportsPreview) {
          return MarkdownView(
            document: parseMarkdown(state.text),
            onLinkTap: (url) => _showLinkDialog(context, url),
          );
        }
        return _buildEditor(context, state);
    }
  }

  Widget _buildEditor(BuildContext context, TextEditorState state) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: scheme.surfaceContainerLow,
          child: Text(
            '${state.scope.displayName}${state.path.displayPath}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (state.saveError != null)
          Material(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: scheme.onErrorContainer),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.saveError!,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              _LineNumberGutter(
                controller: _controller,
                scrollController: _scrollController,
                textStyle: textTheme.bodyMedium!,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  maxLines: null,
                  expands: true,
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['RobotoMono', 'Courier New'],
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    isCollapsed: false,
                  ),
                  textInputAction: TextInputAction.newline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(BuildContext context, TextEditorState state) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: scheme.surfaceContainerLow,
        child: Row(
          children: [
            Icon(
              state.isDirty ? Icons.circle : Icons.check_circle_outline,
              size: 12,
              color: state.isDirty ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              state.isDirty ? '未保存' : '已保存',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Text(
              widget.args.language.displayName,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              _cursorPositionLabel(),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _cursorPositionLabel() {
    final selection = _controller.selection;
    if (!selection.isValid || _controller.text.isEmpty) return '';
    final offset = selection.baseOffset.clamp(0, _controller.text.length);
    final lineBreakIndex = _controller.text.lastIndexOf('\n', offset);
    final line = '\n'.allMatches(_controller.text.take(offset)).length + 1;
    final column = offset - (lineBreakIndex == -1 ? 0 : lineBreakIndex + 1) + 1;
    return '第 $line 行，第 $column 列';
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(textEditorProvider(_editorKey).notifier).save();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
        );
      }
    } on RootfsFileException catch (error) {
      if (!mounted) return;
      if (error.code == RootfsFileErrorCode.conflict) {
        _showConflictDialog(context);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final state = ref.read(textEditorProvider(_editorKey));
    if (!state.isDirty) {
      context.pop();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前有未保存的修改，离开将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      context.pop();
    }
  }

  void _maybePopWithConfirm(BuildContext context) {
    _confirmDiscard(context);
  }

  void _showConflictDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文件已被外部修改'),
        content: const Text('磁盘上的文件已被其他程序修改。已重新加载最新内容。'
            '如需保留你的修改，请先保存为新文件。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }

  void _showLinkDialog(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('链接'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _LineNumberGutter extends StatefulWidget {
  const _LineNumberGutter({
    required this.controller,
    required this.scrollController,
    required this.textStyle,
  });

  final TextFileEditingController controller;
  final ScrollController scrollController;
  final TextStyle textStyle;

  @override
  State<_LineNumberGutter> createState() => _LineNumberGutterState();
}

class _LineNumberGutterState extends State<_LineNumberGutter> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
    widget.scrollController.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    widget.scrollController.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
    final gutterStyle = widget.textStyle.copyWith(
      color: scheme.outline,
      fontSize: widget.textStyle.fontSize! * 0.85,
    );
    final metrics = widget.scrollController.positions.isNotEmpty
        ? widget.scrollController.position
        : null;
    final pixels = metrics?.pixels ?? 0;
    return Container(
      width: 48,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ClipRect(
        child: OverflowBox(
          minWidth: 48,
          maxWidth: 48,
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: Offset(0, -pixels),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 1; i <= lineCount; i++)
                  Text('$i', style: gutterStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

extension on String {
  String take(int count) => substring(0, count.clamp(0, length));
}
