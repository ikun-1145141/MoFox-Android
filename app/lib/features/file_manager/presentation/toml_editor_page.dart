import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/toml_editor_notifier.dart';
import '../application/toml_editor_state.dart';
import '../domain/rootfs_file_exception.dart';
import '../domain/rootfs_file_models.dart';
import '../domain/toml_diagnostic.dart';
import 'widgets/toml_editing_controller.dart';

/// TOML 文件编辑页。
///
/// 使用 Flutter 原生 [EditableText] + 自定义 [TomlEditingController] 实现语法
/// 高亮。显式保存，保存前强制重新校验；存在错误级诊断时禁用保存按钮。
/// 返回时有未保存修改时弹出确认对话框。
class TomlEditorPage extends ConsumerStatefulWidget {
  const TomlEditorPage({required this.args, super.key});

  final TomlEditorRouteArgs args;

  @override
  ConsumerState<TomlEditorPage> createState() => _TomlEditorPageState();
}

class _TomlEditorPageState extends ConsumerState<TomlEditorPage> {
  late final TomlEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  bool _controllerSynced = false;

  @override
  void initState() {
    super.initState();
    _controller = TomlEditingController();
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_controllerSynced) return;
    ref
        .read(tomlEditorProvider(_editorKey).notifier)
        .updateText(_controller.text);
  }

  TomlEditorKey get _editorKey => TomlEditorKey(
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
    final state = ref.watch(tomlEditorProvider(_editorKey));
    // 首次 ready 时把加载的文本灌入控制器，且只灌一次（避免覆盖用户输入）。
    if (state.loadStatus == TomlEditorLoadStatus.ready && !_controllerSynced) {
      _controllerSynced = true;
      _controller.text = state.text;
    }
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
          title: Text(state.path.name.isEmpty ? 'TOML 编辑器' : state.path.name),
          actions: [
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

  Widget _buildBody(BuildContext context, TomlEditorState state) {
    switch (state.loadStatus) {
      case TomlEditorLoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case TomlEditorLoadStatus.notFound:
        return _StatusView(
          icon: Icons.find_in_page_outlined,
          title: '文件不存在',
          message: '该文件可能已被删除。',
          action: TextButton(
            onPressed: () => context.pop(),
            child: const Text('返回'),
          ),
        );
      case TomlEditorLoadStatus.failed:
        return _StatusView(
          icon: Icons.error_outline,
          title: '加载失败',
          message: state.saveError ?? '未知错误',
          action: TextButton(
            onPressed: () =>
                ref.read(tomlEditorProvider(_editorKey).notifier).reload(),
            child: const Text('重试'),
          ),
        );
      case TomlEditorLoadStatus.idle:
      case TomlEditorLoadStatus.ready:
        return _buildEditor(context, state);
    }
  }

  Widget _buildEditor(BuildContext context, TomlEditorState state) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        // 路径面包屑
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
        // 诊断错误条（如有）
        if (state.hasErrors)
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
                      state.diagnostics
                          .where(
                              (d) => d.severity == TomlDiagnosticSeverity.error)
                          .first
                          .message,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showDiagnosticsSheet(context, state),
                    child: Text(
                      '查看 ${state.diagnostics.where((d) => d.severity == TomlDiagnosticSeverity.error).length} 项',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 编辑器主体
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

  Widget _buildStatusBar(BuildContext context, TomlEditorState state) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final errorCount = state.diagnostics
        .where((d) => d.severity == TomlDiagnosticSeverity.error)
        .length;
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
            if (errorCount > 0)
              Text(
                '$errorCount 错误',
                style: text.bodySmall?.copyWith(color: scheme.error),
              )
            else
              Text(
                '语法正确',
                style: text.bodySmall?.copyWith(color: scheme.primary),
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
    // 保存前强制刷新一次诊断（防抖可能尚未触发）。
    ref.read(tomlEditorProvider(_editorKey).notifier).refreshDiagnostics();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tomlEditorProvider(_editorKey).notifier).save();
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
        messenger.showSnackBar(
          SnackBar(content: Text(state_saveErrorOrFallback(error))),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final state = ref.read(tomlEditorProvider(_editorKey));
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

  void _showDiagnosticsSheet(BuildContext context, TomlEditorState state) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('诊断', style: text.titleMedium),
              const SizedBox(height: 12),
              ...state.diagnostics.map((d) {
                final color = d.severity == TomlDiagnosticSeverity.error
                    ? scheme.error
                    : scheme.tertiary;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    d.severity == TomlDiagnosticSeverity.error
                        ? Icons.error_outline
                        : Icons.info_outline,
                    color: color,
                  ),
                  title: Text(d.message),
                  subtitle: d.hasLocation
                      ? Text(d.displayLocation)
                      : const Text('全局'),
                  onTap: d.hasLocation
                      ? () {
                          Navigator.of(ctx).pop();
                          _jumpToDiagnostic(d);
                        }
                      : null,
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _jumpToDiagnostic(TomlDiagnostic d) {
    final line = d.line;
    if (line == null) return;
    final lines = _controller.text.split('\n');
    var offset = 0;
    for (var i = 0; i < line - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    final column = d.column;
    final target = column == null ? offset : offset + (column - 1);
    final clamped = target.clamp(0, _controller.text.length);
    _controller.selection = TextSelection.collapsed(offset: clamped);
    _focusNode.requestFocus();
  }
}

/// 读取 notifier 当前 saveError 或回退到异常 message。
String state_saveErrorOrFallback(RootfsFileException error) {
  return switch (error.code) {
    RootfsFileErrorCode.conflict => '文件已被外部修改',
    RootfsFileErrorCode.notFound => '文件已不存在',
    RootfsFileErrorCode.permissionDenied => '没有写权限',
    _ => error.message,
  };
}

class _LineNumberGutter extends StatefulWidget {
  const _LineNumberGutter({
    required this.controller,
    required this.scrollController,
    required this.textStyle,
  });

  final TomlEditingController controller;
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
