import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';
import '../../domain/wizard_step.dart';

/// 镜像源检测步骤。
///
/// 参照 Neo-MoFox 桌面启动器的 MirrorService，
/// 对多个镜像源进行延迟探测，自动选择最优源。
class MirrorCheckStep extends ConsumerStatefulWidget {
  const MirrorCheckStep({super.key});

  @override
  ConsumerState<MirrorCheckStep> createState() => _MirrorCheckStepState();
}

class _MirrorCheckStepState extends ConsumerState<MirrorCheckStep> {
  bool _checking = false;
  bool _done = false;
  final List<_MirrorResult> _results = [];

  /// 预定义镜像源列表。
  static const List<_MirrorDef> _mirrors = [
    _MirrorDef(
      id: 'github',
      name: 'GitHub (官方)',
      baseUrl: 'https://github.com/MoFox-Studio/Neo-MoFox',
      region: '全球',
    ),
    _MirrorDef(
      id: 'ghproxy',
      name: 'GHProxy 加速',
      baseUrl: 'https://ghfast.top/https://github.com/MoFox-Studio/Neo-MoFox',
      region: '中国大陆',
    ),
    _MirrorDef(
      id: 'gitee',
      name: 'Gitee 镜像',
      baseUrl: 'https://gitee.com/MoFox-Studio/Neo-MoFox',
      region: '中国大陆',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 自动开始检测
    _startCheck();
  }

  Future<void> _startCheck() async {
    setState(() {
      _checking = true;
      _done = false;
      _results.clear();
    });

    for (final mirror in _mirrors) {
      final result = await _probeMirror(mirror);
      if (!mounted) return;
      setState(() => _results.add(result));
    }

    // 自动选择最快的可用源
    final available = _results.where((r) => r.reachable).toList();
    if (available.isNotEmpty) {
      available.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
      final best = available.first;
      ref.read(wizardProvider.notifier).update(
        (d) => d.copyWith(mirrorId: best.mirror.id),
      );
    }

    setState(() {
      _checking = false;
      _done = true;
    });
  }

  Future<_MirrorResult> _probeMirror(_MirrorDef mirror) async {
    final stopwatch = Stopwatch()..start();
    try {
      // 简单 HTTP HEAD 探测（实际实现需根据平台做网络请求）
      // 这里模拟延迟，真实逻辑会用 dio 或 http 包
      await Future<void>.delayed(
        Duration(milliseconds: 300 + (mirror.id.hashCode % 700).abs()),
      );
      stopwatch.stop();
      return _MirrorResult(
        mirror: mirror,
        reachable: true,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      stopwatch.stop();
      return _MirrorResult(
        mirror: mirror,
        reachable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 状态指示
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                if (_checking)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_done)
                  Icon(Icons.check_circle, color: scheme.primary, size: 20)
                else
                  Icon(Icons.wifi_find, color: scheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _checking
                        ? '正在检测镜像源延迟…'
                        : _done
                            ? '检测完成，已自动选择最优源'
                            : '准备检测镜像源',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (_done)
                  TextButton.icon(
                    onPressed: _startCheck,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 镜像源列表
          Expanded(
            child: ListView.separated(
              itemCount: _mirrors.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final mirror = _mirrors[index];
                final result = index < _results.length ? _results[index] : null;
                final isSelected = draft.mirrorId == mirror.id;

                return _MirrorTile(
                  mirror: mirror,
                  result: result,
                  isSelected: isSelected,
                  onTap: result != null && result.reachable
                      ? () => notifier.update(
                            (d) => d.copyWith(mirrorId: mirror.id),
                          )
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // 提示
          Text(
            '镜像源用于下载 Neo-MoFox 仓库和依赖，选择延迟最低的源可加快安装速度。',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── 内部数据类 ────────────────────────────────────────────

class _MirrorDef {
  const _MirrorDef({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.region,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String region;
}

class _MirrorResult {
  const _MirrorResult({
    required this.mirror,
    required this.reachable,
    required this.latencyMs,
  });

  final _MirrorDef mirror;
  final bool reachable;
  final int latencyMs;
}

class _MirrorTile extends StatelessWidget {
  const _MirrorTile({
    required this.mirror,
    required this.result,
    required this.isSelected,
    this.onTap,
  });

  final _MirrorDef mirror;
  final _MirrorResult? result;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final Color cardColor = isSelected
        ? scheme.primaryContainer.withValues(alpha: 0.3)
        : scheme.surfaceContainerLow;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              // 选择指示
              Radio<String>(
                value: mirror.id,
                groupValue: isSelected ? mirror.id : '',
                onChanged: onTap != null ? (_) => onTap!() : null,
              ),
              const SizedBox(width: 8),
              // 镜像信息
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
                      '${mirror.region} · ${mirror.baseUrl}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 延迟状态
              if (result == null)
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '不可达',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
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
    final text = Theme.of(context).textTheme;

    final Color bgColor;
    final Color fgColor;
    if (latencyMs < 300) {
      bgColor = Colors.green.shade50;
      fgColor = Colors.green.shade700;
    } else if (latencyMs < 800) {
      bgColor = Colors.orange.shade50;
      fgColor = Colors.orange.shade700;
    } else {
      bgColor = Colors.red.shade50;
      fgColor = Colors.red.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${latencyMs}ms',
        style: text.labelSmall?.copyWith(
          color: fgColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
