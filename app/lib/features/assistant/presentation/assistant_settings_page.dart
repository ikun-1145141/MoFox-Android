import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/assistant_settings_notifier.dart';
import '../data/assistant_api_client.dart';

class AssistantSettingsPage extends ConsumerStatefulWidget {
  const AssistantSettingsPage({super.key});

  @override
  ConsumerState<AssistantSettingsPage> createState() =>
      _AssistantSettingsPageState();
}

class _AssistantSettingsPageState extends ConsumerState<AssistantSettingsPage> {
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(assistantSettingsProvider.notifier).saveConnection(
            enabled: ref.read(assistantSettingsProvider).valueOrNull?.enabled ??
                false,
            baseUrl: _baseUrlController.text,
            model: _modelController.text,
            apiKey: _apiKeyController.text,
          );
      _apiKeyController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 助手配置已保存')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    await _save();
    setState(() => _testing = true);
    try {
      final settings = await ref.read(assistantSettingsProvider.future);
      final key = await ref.read(assistantCredentialStoreProvider).read();
      if (key == null || key.isEmpty) throw StateError('请填写 API Key');
      await ref.read(assistantApiClientProvider).testConnection(
            settings: settings,
            apiKey: key,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _enableYolo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const YoloConfirmationDialog(),
    );
    if (confirmed == true) {
      await ref.read(assistantSettingsProvider.notifier).enableYolo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(assistantSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (!_loaded && settings != null) {
      _loaded = true;
      _baseUrlController.text = settings.baseUrl;
      _modelController.text = settings.model;
    }
    final busy = _saving || _testing || settingsAsync.isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 运维助手')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SwitchListTile(
            value: settings?.enabled ?? false,
            onChanged: busy
                ? null
                : ref.read(assistantSettingsProvider.notifier).setEnabled,
            title: const Text('启用 AI 助手'),
            subtitle: const Text('切换后立即保存；模型请求会发送到你配置的第三方服务'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlController,
            enabled: !busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://example.com/v1',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings?.allowInsecureHttp ?? false,
            onChanged: busy
                ? null
                : ref
                    .read(assistantSettingsProvider.notifier)
                    .setAllowInsecureHttp,
            title: const Text('允许不安全 HTTP'),
            subtitle: const Text('仅用于你信任的服务；API Key 和对话内容将以明文传输'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: '模型名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            enabled: !busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: settings?.hasApiKey == true
                  ? 'API Key（已保存，留空不修改）'
                  : 'API Key',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _test,
                  child: Text(_testing ? '测试中…' : '保存并测试'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            color: settings?.yoloEnabled == true
                ? Theme.of(context).colorScheme.errorContainer
                : null,
            child: ListTile(
              leading: const Icon(Icons.bolt),
              title: const Text('YOLO 模式'),
              subtitle: Text(
                settings?.yoloEnabled == true
                    ? '已开启：AI 可直接执行任意命令，可在助手面板急停'
                    : '默认关闭；开启后不限制命令，也不再逐项确认',
              ),
              trailing: Switch(
                value: settings?.yoloEnabled ?? false,
                onChanged: settings == null
                    ? null
                    : (value) => value
                        ? _enableYolo()
                        : ref
                            .read(assistantSettingsProvider.notifier)
                            .disableYolo(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: busy
                ? null
                : () => ref.read(assistantSettingsProvider.notifier).clear(),
            icon: const Icon(Icons.delete_outline),
            label: const Text('清除助手配置和凭据'),
          ),
        ],
      ),
    );
  }
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
            'YOLO 会让 AI 在应用的 Linux 运行时中直接执行任意命令，不再逐项确认。'
            '命令可以安装、修改或删除数据；你仍可随时急停。',
          ),
          const SizedBox(height: 16),
          const Text('请输入“开启 YOLO”确认：'),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: _handleChanged,
            onSubmitted: (_) => _confirm(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
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
