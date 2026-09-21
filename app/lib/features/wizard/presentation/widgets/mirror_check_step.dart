import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_network_checks.dart';
import '../../application/wizard_notifier.dart';
import '../../domain/wizard_mirror_source.dart';

/// 对真实仓库端点并发探测，完成前或没有可达源时不得继续。
class MirrorCheckStep extends ConsumerWidget {
  const MirrorCheckStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final check = ref.watch(mirrorCheckProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                if (check.running)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    check.hasReachable
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: check.hasReachable ? scheme.primary : scheme.error,
                    size: 20,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    check.running
                        ? '正在并发检测真实仓库连接…'
                        : check.hasReachable
                            ? '检测完成，请选择可用镜像源'
                            : '没有检测到可用镜像源，请重试',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (check.completed)
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(mirrorCheckProvider.notifier).run(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: wizardMirrorSources.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final mirror = wizardMirrorSources[index];
                final result = check.results[mirror.id];
                return _MirrorTile(
                  mirror: mirror,
                  result: result,
                  checking: check.running,
                  isSelected:
                      result?.reachable == true && draft.mirrorId == mirror.id,
                  onTap: result?.reachable == true
                      ? () => ref
                          .read(mirrorCheckProvider.notifier)
                          .selectMirror(mirror.id)
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '仅实际连接成功的镜像源可被选择；超时或异常会明确标记为不可达。',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MirrorTile extends StatelessWidget {
  const _MirrorTile({
    required this.mirror,
    required this.result,
    required this.checking,
    required this.isSelected,
    this.onTap,
  });

  final WizardMirrorSource mirror;
  final MirrorProbeResult? result;
  final bool checking;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: isSelected
          ? scheme.primaryContainer.withValues(alpha: 0.3)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Radio<String>(
                value: mirror.id,
                groupValue: isSelected ? mirror.id : '',
                onChanged: onTap == null ? null : (_) => onTap!(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      mirror.name,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${mirror.region} · ${mirror.displayUrl}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (result?.errorMessage != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        result!.errorMessage!,
                        style: text.labelSmall?.copyWith(color: scheme.error),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (checking || result == null)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else if (result!.reachable)
                _LatencyBadge(latencyMs: result!.latencyMs)
              else
                _StatusBadge(
                  label: '不可达',
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({required this.latencyMs});

  final int latencyMs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _StatusBadge(
      label: '${latencyMs}ms',
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}
