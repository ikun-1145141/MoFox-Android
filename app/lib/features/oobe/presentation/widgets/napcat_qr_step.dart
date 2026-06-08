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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_2_outlined,
              size: 36,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '扫码登录 QQ',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '用 QQ 客户端「扫一扫」对准下方二维码完成登录。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: payload == null
                  ? const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => ref.invalidate(napcatQrPayloadProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新二维码'),
            ),
          ),
        ],
      ),
    );
  }
}
