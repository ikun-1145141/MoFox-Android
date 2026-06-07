import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Napcat 登录二维码占位。
///
/// 真正的二维码内容会通过 `RuntimeBridge` 监听 Napcat PTY 输出后填充，
/// 这里先放一个占位 payload，等原生侧接通后用 [napcatQrPayloadProvider] 注入。
final napcatQrPayloadProvider = StateProvider<String?>((_) => null);

class NapcatQrStep extends ConsumerWidget {
  const NapcatQrStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = ref.watch(napcatQrPayloadProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('扫码登录 QQ',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '用 QQ 客户端「扫一扫」对准下方二维码完成登录。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (payload == null)
              const SizedBox(
                width: 220,
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(napcatQrPayloadProvider),
              child: const Text('刷新二维码'),
            ),
          ],
        ),
      ),
    );
  }
}
