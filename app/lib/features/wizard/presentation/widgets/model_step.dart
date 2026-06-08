import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';

class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({super.key});

  @override
  ConsumerState<ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends ConsumerState<ModelStep> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            initialValue: draft.apiBaseUrl,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.openai.com/v1',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                notifier.update((d) => d.copyWith(apiBaseUrl: v)),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: draft.apiKey,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-…',
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
          Text(
            '稍后在设置中可随时修改模型与凭据。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
