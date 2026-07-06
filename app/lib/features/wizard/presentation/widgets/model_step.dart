import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/wizard_notifier.dart';

/// 硅基流动 API 密钥获取地址（含邀请码）。
const _siliconFlowKeyUrl = 'https://cloud.siliconflow.cn/i/0ww8zcOn';

class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({super.key});

  @override
  ConsumerState<ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends ConsumerState<ModelStep> {
  bool _obscure = true;

  Future<void> _openGetKey() async {
    final uri = Uri.parse(_siliconFlowKeyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 供应商标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.cloud_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '硅基流动 SiliconFlow',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        '大模型 API 服务商',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // API Key 输入
          TextFormField(
            initialValue: draft.apiKey,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API Key *',
              hintText: '输入你的 API Key',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => notifier.update((d) => d.copyWith(apiKey: v)),
          ),
          const SizedBox(height: 12),
          // 获取密钥按钮
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openGetKey,
              icon: const Icon(Icons.key, size: 18),
              label: const Text('获取密钥'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '模型与请求地址已预置，稍后在设置中可随时修改。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
