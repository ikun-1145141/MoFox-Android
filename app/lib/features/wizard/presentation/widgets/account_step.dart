import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';
import '../../domain/wizard_validation.dart';

class AccountStep extends ConsumerWidget {
  const AccountStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final digits = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(12),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            key: const ValueKey<String>('wizard-bot-qq'),
            initialValue: draft.botQq,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            maxLength: 12,
            decoration: InputDecoration(
              labelText: 'Bot QQ 号',
              hintText: '机器人将登录的 QQ',
              prefixIcon: const Icon(Icons.smart_toy_outlined),
              border: const OutlineInputBorder(),
              errorText: WizardValidation.qq(draft.botQq, label: 'Bot QQ'),
            ),
            onChanged: (v) => notifier.update((d) => d.copyWith(botQq: v)),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: draft.botNickname,
            decoration: const InputDecoration(
              labelText: 'Bot 昵称（可选）',
              hintText: '机器人对外显示的名字',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                notifier.update((d) => d.copyWith(botNickname: v)),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey<String>('wizard-owner-qq'),
            initialValue: draft.ownerQq,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            maxLength: 12,
            decoration: InputDecoration(
              labelText: '主人 QQ',
              hintText: '拥有最高权限的管理员账号',
              prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
              border: const OutlineInputBorder(),
              errorText: WizardValidation.qq(draft.ownerQq, label: '主人 QQ'),
            ),
            onChanged: (v) => notifier.update((d) => d.copyWith(ownerQq: v)),
          ),
        ],
      ),
    );
  }
}
