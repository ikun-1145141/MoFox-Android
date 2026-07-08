import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';

class NetworkStep extends ConsumerStatefulWidget {
  const NetworkStep({super.key});

  @override
  ConsumerState<NetworkStep> createState() => _NetworkStepState();
}

class _NetworkStepState extends ConsumerState<NetworkStep> {
  late final TextEditingController _webuiKeyController;

  @override
  void initState() {
    super.initState();
    _webuiKeyController = TextEditingController(
      text: ref.read(wizardProvider).draft.webuiApiKey,
    );
  }

  @override
  void dispose() {
    _webuiKeyController.dispose();
    super.dispose();
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
          TextFormField(
            initialValue: '${draft.wsPort}',
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'WebSocket 端口',
              hintText: '8095',
              prefixIcon: Icon(Icons.lan_outlined),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              final n = int.tryParse(v) ?? 0;
              notifier.update((d) => d.copyWith(wsPort: n));
            },
          ),
          const SizedBox(height: 16),
          Text('更新通道', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'main',
                label: Text('稳定版'),
                icon: Icon(Icons.verified_outlined),
              ),
              ButtonSegment<String>(
                value: 'dev',
                label: Text('开发版'),
                icon: Icon(Icons.science_outlined),
              ),
            ],
            selected: <String>{draft.channel},
            onSelectionChanged: (s) =>
                notifier.update((d) => d.copyWith(channel: s.first)),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('安装 WebUI 管理面板'),
            subtitle: const Text('在浏览器中可视化管理 Bot'),
            value: draft.installWebui,
            onChanged: (value) {
              notifier.update(
                (d) => d.copyWith(
                  installWebui: value,
                  webuiApiKey: value ? d.webuiApiKey : '',
                ),
              );
              if (!value) _webuiKeyController.clear();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: _webuiKeyController,
                  enabled: draft.installWebui,
                  decoration: const InputDecoration(
                    labelText: 'WebUI 访问密钥',
                    hintText: '启用 WebUI 后点击右侧骰子生成',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      notifier.update((d) => d.copyWith(webuiApiKey: v)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '随机生成',
                onPressed: draft.installWebui
                    ? () {
                        final key = _randomKey();
                        _webuiKeyController.text = key;
                        _webuiKeyController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: key.length),
                        );
                        notifier.update(
                          (d) => d.copyWith(webuiApiKey: key),
                        );
                      }
                    : null,
                icon: const Icon(Icons.casino_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (draft.installWebui && draft.webuiApiKey.isNotEmpty)
            _StrengthBar(strength: _strength(draft.webuiApiKey)),
          const SizedBox(height: 12),
          Text(
            draft.installWebui
                ? '密钥用于访问 WebUI 管理面板，请妥善保管。'
                : '关闭后将跳过 WebUI 构建，也不需要填写访问密钥。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  static String _randomKey() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static double _strength(String key) {
    // 0..1 大致估算
    var s = 0.0;
    if (key.length >= 8) s += 0.25;
    if (key.length >= 16) s += 0.25;
    if (RegExp('[A-Z]').hasMatch(key) && RegExp('[a-z]').hasMatch(key)) {
      s += 0.25;
    }
    if (RegExp(r'\d').hasMatch(key)) s += 0.25;
    return s;
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength});
  final double strength;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = strength < 0.5
        ? scheme.error
        : strength < 0.75
            ? scheme.tertiary
            : scheme.primary;
    final label = strength < 0.5
        ? '强度：弱'
        : strength < 0.75
            ? '强度：中'
            : '强度：强';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: strength,
            minHeight: 4,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
