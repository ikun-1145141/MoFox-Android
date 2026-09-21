import 'package:flutter/material.dart';

import 'package:mofox_android/core/theme/app_theme.dart';

/// 将内容限制在适合阅读的宽度内，并在大屏上自动增加页边距。
class AppAdaptiveContent extends StatelessWidget {
  const AppAdaptiveContent({
    required this.child,
    this.maxWidth = 840,
    this.padding,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= 600 ? AppSpacing.xl : AppSpacing.lg;
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding ?? EdgeInsets.symmetric(horizontal: horizontal),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 设置类页面的统一滚动容器。
class AppPageList extends StatelessWidget {
  const AppPageList({
    required this.children,
    this.maxWidth = 840,
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              constraints.maxWidth >= 600 ? AppSpacing.xl : AppSpacing.lg;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.sm,
              horizontal,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    required this.title,
    required this.children,
    this.addDividers = true,
    this.contentPadding,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final bool addDividers;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contents = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0 && addDividers) contents.add(const AppSectionDivider());
      contents.add(children[index]);
    }

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: contents,
    );
    if (contentPadding != null) {
      body = Padding(padding: contentPadding!, child: body);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
        ),
        Card(child: body),
      ],
    );
  }
}

class AppSectionDivider extends StatelessWidget {
  const AppSectionDivider({this.indent = 72, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Divider(height: 1, indent: indent),
    );
  }
}

class AppSettingTile extends StatelessWidget {
  const AppSettingTile({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: ListTile(
          enabled: enabled,
          leading: leading,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: trailing,
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}

class AppSwitchSettingTile extends StatelessWidget {
  const AppSwitchSettingTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: secondary,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
      ),
    );
  }
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    this.label = '正在加载',
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.lg),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _AppMessageState(
      semanticLabel: message == null ? title : '$title，$message',
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    this.title = '加载失败',
    this.message = '请检查后重试。',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _AppMessageState(
      semanticLabel: '$title，$message',
      icon: Icons.error_outline,
      title: title,
      message: message,
      iconColor: Theme.of(context).colorScheme.error,
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
    );
  }
}

class _AppMessageState extends StatelessWidget {
  const _AppMessageState({
    required this.semanticLabel,
    required this.icon,
    required this.title,
    this.message,
    this.iconColor,
    this.action,
  });

  final String semanticLabel;
  final IconData icon;
  final String title;
  final String? message;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: semanticLabel,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        icon,
                        size: 48,
                        color: iconColor ?? scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge,
                      ),
                      if (message != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum AppStatusTone { success, warning, error, info, neutral }

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, defaultIcon) = switch (tone) {
      AppStatusTone.success => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
      AppStatusTone.warning => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.warning_amber_rounded,
        ),
      AppStatusTone.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
        ),
      AppStatusTone.info => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.info_outline,
        ),
      AppStatusTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.pause_circle_outline,
        ),
    };

    return Semantics(
      container: true,
      label: '状态：$label',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: ShapeDecoration(
            color: background,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon ?? defaultIcon, size: 16, color: foreground),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
