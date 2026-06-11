import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';
import '../../domain/wizard_step.dart';

class SummaryStep extends ConsumerWidget {
  const SummaryStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardProvider);
    final notifier = ref.read(wizardProvider.notifier);
    final draft = state.draft;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _Group(
          title: '安装准备',
          rows: <_Row>[
            _Row('用户协议', draft.eulaAccepted ? '已同意' : '未同意'),
            _Row('镜像源', draft.mirrorId),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          title: '实例信息',
          onEdit: () => notifier.goTo(WizardStep.instanceInfo),
          rows: <_Row>[_Row('名称', draft.name)],
        ),
        const SizedBox(height: 12),
        _Group(
          title: '账号',
          onEdit: () => notifier.goTo(WizardStep.account),
          rows: <_Row>[
            _Row('Bot QQ', draft.botQq),
            if (draft.botNickname.isNotEmpty)
              _Row('昵称', draft.botNickname),
            _Row('主人 QQ', draft.ownerQq),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          title: '模型',
          onEdit: () => notifier.goTo(WizardStep.model),
          rows: <_Row>[
            _Row('Base URL', draft.apiBaseUrl),
            _Row('API Key', _mask(draft.apiKey)),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          title: '网络',
          onEdit: () => notifier.goTo(WizardStep.network),
          rows: <_Row>[
            _Row('WS 端口', '${draft.wsPort}'),
            _Row('通道', draft.channel == 'main' ? '稳定版' : '开发版'),
            _Row('WebUI 密钥', _mask(draft.webuiApiKey)),
          ],
        ),
        const SizedBox(height: 12),
        _Group(
          title: '组件',
          rows: const <_Row>[
            _Row('NapCat', '默认安装并配置'),
            _Row('WebUI', '默认安装'),
          ],
        ),
      ],
    );
  }

  static String _mask(String value) {
    if (value.isEmpty) return '（未设置）';
    if (value.length <= 6) return '••••••';
    return '${value.substring(0, 3)}••••${value.substring(value.length - 3)}';
  }
}

class _Row {
  const _Row(this.label, this.value);
  final String label;
  final String value;
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.rows,
    this.onEdit,
  });
  final String title;
  final List<_Row> rows;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('修改'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 96,
                    child: Text(
                      r.label,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.value.isEmpty ? '（未填写）' : r.value,
                      style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
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
