import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mofox_android/core/platform/screen_wake_lock.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:qr_flutter/qr_flutter.dart';

class NapcatQrSheet extends StatelessWidget {
  const NapcatQrSheet({required this.payload, this.onCancel, super.key});
  final String payload;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final imagePath = napcatQrImagePath(payload);
    final copyableLoginInfo = napcatQrCopyableLoginInfo(payload);
    return ScreenWakeLockScope(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final qrSize = (constraints.maxWidth - 80).clamp(140.0, 220.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(
                          '使用 QQ 扫码登录',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '在 QQ → 头像 → 扫一扫 中扫描下方二维码',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        child: imagePath == null
                            ? QrImageView(
                                data: payload,
                                size: qrSize,
                                backgroundColor: Colors.white,
                                semanticsLabel: 'QQ 登录二维码',
                              )
                            : _QrFileImage(
                                path: imagePath,
                                cacheKey: payload,
                                errorColor: scheme.error,
                                size: qrSize,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const AppStatusBadge(
                        label: '等待扫描',
                        tone: AppStatusTone.info,
                        icon: Icons.hourglass_top,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        copyableLoginInfo == null
                            ? '当前二维码由 NapCat 以图片生成，无法提取可复制的登录信息。可使用另一台设备扫码，或请可信任的人协助。'
                            : '无法使用视觉扫码时，可复制一次性登录信息到受信任的 QQ 登录流程。复制内容可能包含敏感凭据，请勿分享。',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (copyableLoginInfo != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _confirmAndCopy(
                              context,
                              copyableLoginInfo,
                            ),
                            icon: const Icon(Icons.content_copy),
                            label: const Text('复制登录信息'),
                          ),
                        ),
                      ],
                      if (onCancel != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onCancel,
                            icon: const Icon(Icons.close),
                            label: const Text('取消登录'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmAndCopy(
    BuildContext context,
    String loginInfo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.content_copy),
        title: const Text('复制登录信息？'),
        content: const Text(
          '登录信息可能包含一次性敏感凭据。只粘贴到受信任的 QQ 登录流程，并在使用后清空剪贴板。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('复制'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: loginInfo));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录信息已复制；使用后请清空剪贴板')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制登录信息失败')),
      );
    }
  }
}

/// 从带刷新版本的 `file:<path>#<version>` payload 中取出真实文件路径。
String? napcatQrImagePath(String payload) {
  if (!payload.startsWith('file:')) return null;
  final value = payload.substring('file:'.length);
  final versionSeparator = value.lastIndexOf('#');
  return versionSeparator > 0 ? value.substring(0, versionSeparator) : value;
}

/// 仅返回二维码本身携带的登录信息；本地图片路径不是可用的登录凭据。
String? napcatQrCopyableLoginInfo(String payload) {
  final value = payload.trim();
  if (value.isEmpty || napcatQrImagePath(value) != null) return null;
  return value;
}

/// 绕过 FileImage 的路径缓存，直接读取当前二维码文件内容。
Uint8List napcatQrImageBytes(String payload) {
  final path = napcatQrImagePath(payload);
  if (path == null) throw ArgumentError('payload 必须引用本地二维码文件');
  return File(path).readAsBytesSync();
}

/// 每次 [cacheKey] 改变都重新读取二维码字节。
///
/// 不能直接使用 Image.file：NapCat 始终覆盖同一个 qrcode.png，FileImage 会按路径
/// 命中 Flutter ImageCache，从而继续显示上一张已经过期的二维码。
class _QrFileImage extends StatefulWidget {
  const _QrFileImage({
    required this.path,
    required this.cacheKey,
    required this.errorColor,
    required this.size,
  });

  final String path;
  final String cacheKey;
  final Color errorColor;
  final double size;

  @override
  State<_QrFileImage> createState() => _QrFileImageState();
}

class _QrFileImageState extends State<_QrFileImage> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _QrFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cacheKey != oldWidget.cacheKey ||
        widget.path != oldWidget.path) {
      _loadBytes();
    }
  }

  void _loadBytes() {
    try {
      _bytes = napcatQrImageBytes(widget.cacheKey);
      _error = null;
    } on Object catch (error) {
      _bytes = null;
      _error = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || _bytes == null) return _errorView();
    return Image.memory(
      _bytes!,
      key: ValueKey<String>(widget.cacheKey),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      semanticLabel: 'QQ 登录二维码',
      errorBuilder: (_, __, ___) => _errorView(),
    );
  }

  Widget _errorView() => Semantics(
        container: true,
        liveRegion: true,
        label: '二维码加载失败，请取消后重试',
        child: ExcludeSemantics(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: widget.errorColor,
                size: 40,
              ),
            ),
          ),
        ),
      );
}
