import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mofox_android/app/router/app_router.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repositoryUrl = 'https://github.com/ikun-1145141/MoFox-Android';

// 进程级状态：应用每次启动自然重置，不落盘、不跨启动。
int _headerTapCount = 0;
bool _easterEggUnlocked = false;
const _easterEggVideoUrl =
    'https://www.bilibili.com/video/BV1GJ411x7h7/?spm_id_from=333.337.search-card.all.click';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  void _handleHeaderTap() {
    if (_easterEggUnlocked) return;
    _headerTapCount += 1;
    if (_headerTapCount >= 10) {
      setState(() => _easterEggUnlocked = true);
    }
  }

  Future<void> _openEasterEggVideo(BuildContext context) async {
    try {
      final launched = await launchUrl(
        Uri.parse(_easterEggVideoUrl),
        mode: LaunchMode.externalApplication,
      );
      if (launched || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器，请稍后重试')),
      );
    }
  }

  Future<void> _copyRepositoryUrl(BuildContext context) async {
    try {
      await Clipboard.setData(const ClipboardData(text: _repositoryUrl));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制 GitHub 链接')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制失败，请手动打开 GitHub')),
      );
    }
  }

  Future<void> _openRepository(BuildContext context) async {
    try {
      final launched = await launchUrl(
        Uri.parse(_repositoryUrl),
        mode: LaunchMode.externalApplication,
      );
      if (launched || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = ref.watch(_packageInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: packageInfo.when(
        loading: () => const AppLoadingState(label: '正在读取应用信息'),
        error: (_, __) => AppErrorState(
          title: '应用信息读取失败',
          message: '无法读取当前版本信息，请重试。',
          onRetry: () => ref.invalidate(_packageInfoProvider),
        ),
        data: (info) => AppPageList(
          children: <Widget>[
            _AppHeaderCard(
              version: '${info.version} (${info.buildNumber})',
              onTitleTap: _handleHeaderTap,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppSectionCard(
              title: '关于',
              children: <Widget>[
                AppSettingTile(
                  leading: const Icon(Icons.code_outlined),
                  title: '查看源代码',
                  subtitle: '在 GitHub 上查看源代码',
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openRepository(context),
                ),
                AppSettingTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: '第三方库许可',
                  subtitle: '查看本应用使用的开源库及许可证信息',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoute.thirdPartyLicenses),
                ),
                const AppSettingTile(
                  leading: Icon(Icons.verified_user_outlined),
                  title: '开放源代码许可',
                  subtitle: 'GNU Affero General Public License v3.0',
                ),
                AppSettingTile(
                  leading: const Icon(Icons.link_outlined),
                  title: '项目链接',
                  subtitle: '复制 GitHub 仓库链接',
                  trailing: const Icon(Icons.content_copy),
                  onTap: () => _copyRepositoryUrl(context),
                ),
                if (_easterEggUnlocked)
                  AppSettingTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: '点击查看一闪女装',
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _openEasterEggVideo(context),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHeaderCard extends StatelessWidget {
  const _AppHeaderCard({required this.version, this.onTitleTap});

  final String version;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: 'MoFox Android，版本 $version，AGPL 3.0 开源许可',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: 28,
            ),
            child: Column(
              children: <Widget>[
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    color: scheme.primaryContainer,
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    size: 48,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTitleTap,
                  child: Text(
                    'MoFox Android',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
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
        ),
      ),
    );
  }
}
