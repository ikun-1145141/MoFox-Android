import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';

class AccountStep extends ConsumerWidget {
  const AccountStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final digits = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            initialValue: draft.botQq,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(
              labelText: 'Bot QQ 号',
              hintText: '机器人将登录的 QQ',
              prefixIcon: Icon(Icons.smart_toy_outlined),
              border: OutlineInputBorder(),
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
            initialValue: draft.ownerQq,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(
              labelText: '主人 QQ',
              hintText: '拥有最高权限的管理员账号',
              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => notifier.update((d) => d.copyWith(ownerQq: v)),
          ),
        ],
      ),
    );
  }
}
