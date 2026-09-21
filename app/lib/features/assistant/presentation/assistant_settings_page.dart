import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/assistant/application/assistant_settings_notifier.dart';
import 'package:mofox_android/features/assistant/data/assistant_api_client.dart';

class AssistantSettingsPage extends ConsumerStatefulWidget {
  const AssistantSettingsPage({super.key});

  @override
  ConsumerState<AssistantSettingsPage> createState() =>
      _AssistantSettingsPageState();
}

class _AssistantSettingsPageState extends ConsumerState<AssistantSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<bool> _save({bool showSuccess = true}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final current = ref.read(assistantSettingsProvider).valueOrNull;
    if (current == null) {
      _showMessage('配置尚未加载完成，请稍后重试');
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref.read(assistantSettingsProvider.notifier).saveConnection(
            enabled: current.enabled,
            baseUrl: _baseUrlController.text,
            model: _modelController.text,
            apiKey: _apiKeyController.text,
          );
      _apiKeyController.clear();
      if (showSuccess) _showMessage('AI 助手配置已保存');
      return true;
    } on Object catch (error) {
      _showMessage('保存失败：${_readableError(error)}');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final saved = await _save(showSuccess: false);
    if (!saved || !mounted) return;
    setState(() => _testing = true);
    try {
      final settings = await ref.read(assistantSettingsProvider.future);
      final key = await ref.read(assistantCredentialStoreProvider).read();
      if (key == null || key.isEmpty) throw StateError('请填写 API Key');
      await ref.read(assistantApiClientProvider).testConnection(
            settings: settings,
            apiKey: key,
          );
      _showMessage('连接成功');
    } on Object catch (error) {
      _showMessage('连接失败：${_readableError(error)}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    try {
      await ref.read(assistantSettingsProvider.notifier).setEnabled(value);
    } on Object catch (error) {
      _showMessage('保存启用状态失败：${_readableError(error)}');
    }
  }

  Future<void> _setAllowInsecureHttp(bool value) async {
    try {
      await ref
          .read(assistantSettingsProvider.notifier)
          .setAllowInsecureHttp(value);
    } on Object catch (error) {
      _showMessage('保存网络安全设置失败：${_readableError(error)}');
    }
  }

  Future<void> _enableYolo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const YoloConfirmationDialog(),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(assistantSettingsProvider.notifier).enableYolo();
    } on Object catch (error) {
      _showMessage('开启 YOLO 失败：${_readableError(error)}');
    }
  }

  Future<void> _disableYolo() async {
    try {
      await ref.read(assistantSettingsProvider.notifier).disableYolo();
    } on Object catch (error) {
      _showMessage('关闭 YOLO 失败：${_readableError(error)}');
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('清除助手配置？'),
        content: const Text('将删除服务地址、模型名称、API Key 和操作模式。此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(assistantSettingsProvider.notifier).clear();
      _baseUrlController.clear();
      _modelController.clear();
      _apiKeyController.clear();
      _showMessage('助手配置和凭据已清除');
    } on Object catch (error) {
      _showMessage('清除失败：${_readableError(error)}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(assistantSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 运维助手')),
      body: settingsAsync.when(
        loading: () => const AppLoadingState(label: '正在加载 AI 助手配置'),
        error: (_, __) => AppErrorState(
          title: 'AI 助手配置加载失败',
          message: '无法读取本机保存的模型配置和凭据状态。',
          onRetry: () => ref.invalidate(assistantSettingsProvider),
        ),
        data: (settings) {
          if (!_loaded) {
            _loaded = true;
            _baseUrlController.text = settings.baseUrl;
            _modelController.text = settings.model;
          }
          final busy = _saving || _testing;
          return Form(
            key: _formKey,
            child: AppPageList(
              children: <Widget>[
                AppSectionCard(
                  title: '服务',
                  children: <Widget>[
                    AppSwitchSettingTile(
                      secondary: const Icon(Icons.auto_awesome_outlined),
                      title: '启用 AI 助手',
                      subtitle: '模型请求会发送到你配置的第三方服务',
                      value: settings.enabled,
                      onChanged: busy ? null : _setEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  title: '连接',
                  addDividers: false,
                  contentPadding: const EdgeInsets.all(AppSpacing.lg),
                  children: <Widget>[
                    TextFormField(
                      controller: _baseUrlController,
                      enabled: !busy,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) => _validateBaseUrl(
                        value,
                        allowInsecureHttp: settings.allowInsecureHttp,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'https://example.com/v1',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _modelController,
                      enabled: !busy,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? '请输入模型名称'
                              : null,
                      decoration: const InputDecoration(
                        labelText: '模型名称',
                        hintText: '例如 gpt-4.1-mini',
                        prefixIcon: Icon(Icons.model_training_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _apiKeyController,
                      enabled: !busy,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (settings.hasApiKey ||
                            (value != null && value.trim().isNotEmpty)) {
                          return null;
                        }
                        return '请输入 API Key';
                      },
                      decoration: InputDecoration(
                        labelText: settings.hasApiKey
                            ? 'API Key（已保存，留空不修改）'
                            : 'API Key',
                        prefixIcon: const Icon(Icons.key_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final testButton = OutlinedButton.icon(
                          onPressed: busy ? null : _test,
                          icon: _testing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.network_check),
                          label: Text(_testing ? '测试中…' : '保存并测试'),
                        );
                        final saveButton = FilledButton.icon(
                          onPressed: busy ? null : _save,
                          icon: _saving
                              ? SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? '保存中…' : '保存'),
                        );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              testButton,
                              const SizedBox(height: AppSpacing.sm),
                              saveButton,
                            ],
                          );
                        }
                        return Row(
                          children: <Widget>[
                            Expanded(child: testButton),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: saveButton),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  title: '网络安全',
                  children: <Widget>[
                    AppSwitchSettingTile(
                      secondary: const Icon(Icons.no_encryption_outlined),
                      title: '允许不安全 HTTP',
                      subtitle: '仅用于可信服务；API Key 和对话内容会以明文传输',
                      value: settings.allowInsecureHttp,
                      onChanged: busy ? null : _setAllowInsecureHttp,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  title: '操作模式',
                  children: <Widget>[
                    AppSwitchSettingTile(
                      secondary: Icon(
                        Icons.bolt,
                        color: settings.yoloEnabled
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      title: 'YOLO 模式',
                      subtitle: settings.yoloEnabled
                          ? '已开启：AI 可直接执行任意命令，可在助手面板急停'
                          : '默认关闭；开启后不限制命令，也不再逐项确认',
                      value: settings.yoloEnabled,
                      onChanged: busy
                          ? null
                          : (value) => value ? _enableYolo() : _disableYolo(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: TextButton.icon(
                    onPressed: busy ? null : _clear,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清除助手配置和凭据'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String? _validateBaseUrl(
  String? value, {
  required bool allowInsecureHttp,
}) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return '请输入 API Base URL';
  final uri = Uri.tryParse(input);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return '请输入完整的 HTTP 或 HTTPS 地址';
  }
  if (uri.scheme == 'http' && !allowInsecureHttp) {
    return 'HTTP 未加密；请改用 HTTPS 或先开启“不安全 HTTP”';
  }
  return null;
}

String _readableError(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ')
      ? text.substring('Exception: '.length)
      : text;
}

class YoloConfirmationDialog extends StatefulWidget {
  const YoloConfirmationDialog({super.key});

  @override
  State<YoloConfirmationDialog> createState() => _YoloConfirmationDialogState();
}

class _YoloConfirmationDialogState extends State<YoloConfirmationDialog> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    final valid = value.trim() == '开启 YOLO';
    if (valid != _valid) setState(() => _valid = valid);
  }

  void _confirm() {
    if (_valid) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('开启 YOLO 模式？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'YOLO 会让 AI 在应用的 Linux 运行时中直接执行任意命令，不再逐项确认。命令可以安装、修改或删除数据；你仍可随时急停。',
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('请输入“开启 YOLO”确认：'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: _handleChanged,
            onSubmitted: (_) => _confirm(),
            decoration: const InputDecoration(hintText: '开启 YOLO'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _valid ? _confirm : null,
          child: const Text('确认开启'),
        ),
      ],
    );
  }
}
