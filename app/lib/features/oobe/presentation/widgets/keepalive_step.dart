import 'package:flutter/material.dart';

/// OOBE 第 3 步：保活授权引导。
///
/// 真实跳转由 [RuntimeBridge] 暴露的 platform channel 触发，这里 UI 部分
/// 用 placeholder 按钮展示意图。
class KeepaliveStep extends StatelessWidget {
  const KeepaliveStep({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.battery_saver_outlined,
              size: 44,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '配置后台保活',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '为避免系统在后台杀掉 Bot 进程，请按下方提示授权三项设置。',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _PermTile(
            icon: Icons.notifications_active_outlined,
            title: '通知权限',
            description: '前台服务依赖持久通知保活。',
            actionLabel: '去授权',
          ),
          const SizedBox(height: 12),
          _PermTile(
            icon: Icons.battery_charging_full_outlined,
            title: '忽略电池优化',
            description: '允许 MoFox 在后台持续运行。',
            actionLabel: '去设置',
          ),
          const SizedBox(height: 12),
          _PermTile(
            icon: Icons.lock_outline,
            title: '应用锁定',
            description: '在最近任务里锁定 MoFox，防止滑掉时被结束。',
            actionLabel: '说明',
          ),
        ],
      ),
    );
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () {},
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
