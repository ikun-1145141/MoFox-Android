import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_network_checks.dart';
import '../../application/wizard_notifier.dart';

/// EULA 只有成功加载后才能勾选；加载中或失败时向导下一步也会保持禁用。
class EulaStep extends ConsumerWidget {
  const EulaStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final document = ref.watch(eulaDocumentProvider(draft.mirrorId));
    final loaded =
        document.hasValue && !document.isLoading && !document.hasError;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    void setAccepted(bool value) {
      if (!loaded) return;
      notifier.update((current) => current.copyWith(eulaAccepted: value));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: document.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => _EulaErrorView(
                    message: error.toString(),
                    onRetry: () =>
                        ref.invalidate(eulaDocumentProvider(draft.mirrorId)),
                  ),
                  data: (value) => _EulaContent(document: value),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: loaded && draft.eulaAccepted
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: loaded ? () => setAccepted(!draft.eulaAccepted) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: <Widget>[
                    Checkbox(
                      value: loaded && draft.eulaAccepted,
                      onChanged: loaded
                          ? (value) => setAccepted(value ?? false)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loaded ? '我已阅读并同意上述用户许可协议' : '协议成功加载后才能勾选同意',
                        style: text.bodyMedium?.copyWith(
                          color: loaded
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EulaContent extends StatelessWidget {
  const _EulaContent({required this.document});

  final EulaDocument document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Neo-MoFox 用户许可协议',
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '镜像源：${document.source.name}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SelectableText(
            document.content,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _EulaErrorView extends StatelessWidget {
  const _EulaErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, color: scheme.error, size: 36),
            const SizedBox(height: 12),
            Text(
              'EULA 获取失败',
              style: text.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '协议未加载成功，不能勾选同意或继续。\n$message',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新获取'),
            ),
          ],
        ),
      ),
    );
  }
}
