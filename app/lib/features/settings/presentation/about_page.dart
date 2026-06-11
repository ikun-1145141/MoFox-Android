import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/router/app_router.dart';

const _repositoryUrl = 'https://github.com/ikun-1145141/MoFox-Android';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(_packageInfoProvider);
    final version = packageInfo.maybeWhen(
      data: (info) => '${info.version} (${info.buildNumber})',
      orElse: () => '读取中',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _AppHeaderCard(version: version),
          const SizedBox(height: 24),
          const _SectionTitle('关于'),
          _ActionCard(
            children: <Widget>[
              _AboutActionTile(
                icon: Icons.code_outlined,
                title: '查看源代码',
                subtitle: '在 GitHub 上查看源代码',
                onTap: () => _copyRepositoryUrl(context),
              ),
              const _Divider(),
              _AboutActionTile(
                icon: Icons.gavel_outlined,
                title: '第三方库许可',
                subtitle: '查看本应用使用的开源库及许可证信息',
                onTap: () => context.push(AppRoute.thirdPartyLicenses),
              ),
              const _Divider(),
              const _AboutActionTile(
                icon: Icons.verified_user_outlined,
                title: '开放源代码许可',
                subtitle: 'GNU Affero General Public License v3.0',
              ),
              const _Divider(),
              _AboutActionTile(
                icon: Icons.link_outlined,
                title: '项目链接',
                subtitle: '复制 GitHub 仓库链接',
                onTap: () => _copyRepositoryUrl(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyRepositoryUrl(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _repositoryUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 GitHub 链接')),
    );
  }
}

class _AppHeaderCard extends StatelessWidget {
  const _AppHeaderCard({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: scheme.primaryContainer,
              ),
              child: Icon(
                Icons.android,
                size: 52,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'MoFox Android',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '版本 $version',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'AGPL-3.0 开源许可',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(child: Column(children: children));
  }
}

class _AboutActionTile extends StatelessWidget {
  const _AboutActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 72),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
