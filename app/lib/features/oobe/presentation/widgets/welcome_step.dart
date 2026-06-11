import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OOBE 第 1 步：欢迎页 + 用户协议要点。
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

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
              Icons.waving_hand_outlined,
              size: 44,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '欢迎使用 MoFox',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '一站式部署 Neo-MoFox 机器人。继续之前请阅读以下要点：',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _Bullet(
            icon: Icons.gavel_outlined,
            title: '用户协议',
            description: '使用本程序即表示同意 Neo-MoFox 的开源协议与 EULA。',
          ),
          _Bullet(
            icon: Icons.privacy_tip_outlined,
            title: '隐私政策',
            description: '所有数据保存在本机 App 私有目录，不上传任何第三方服务器。',
          ),
          _Bullet(
            icon: Icons.bolt_outlined,
            title: '前台保活',
            description: '运行 Bot 时会启动前台服务以避免系统杀进程，会有持久通知。',
          ),
          const SizedBox(height: 8),
          _LegalDocumentButton(
            icon: Icons.description_outlined,
            title: '阅读最终用户许可协议',
            assetPath: '../eula.md',
          ),
          const SizedBox(height: 8),
          _LegalDocumentButton(
            icon: Icons.policy_outlined,
            title: '阅读遥测隐私协议',
            assetPath: '../PRIVACY.md',
          ),
          const SizedBox(height: 16),
          Text(
            '点击“同意并继续”即表示你已阅读、理解并同意上述协议。',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalDocumentButton extends StatelessWidget {
  const _LegalDocumentButton({
    required this.icon,
    required this.title,
    required this.assetPath,
  });

  final IconData icon;
  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: () => _showLegalDocument(context, title, assetPath),
      icon: Icon(icon),
      label: Text(title),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

Future<void> _showLegalDocument(
  BuildContext context,
  String title,
  String assetPath,
) async {
  final body = await rootBundle.loadString(assetPath);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LegalDocumentSheet(title: title, body: body),
  );
}

class _LegalDocumentSheet extends StatelessWidget {
  const _LegalDocumentSheet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                title,
                style: text.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SelectableText(
                    body,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
