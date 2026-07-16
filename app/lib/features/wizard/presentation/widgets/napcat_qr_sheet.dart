import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '使用 QQ 扫码登录',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在 QQ → 头像 → 扫一扫 中扫描下方二维码',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: imagePath == null
                  ? QrImageView(
                      data: payload,
                      size: 220,
                      backgroundColor: Colors.white,
                    )
                  : _QrFileImage(
                      path: imagePath,
                      cacheKey: payload,
                      errorColor: scheme.error,
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  '等待扫描…',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (onCancel != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('取消登录'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 从带刷新版本的 `file:<path>#<version>` payload 中取出真实文件路径。
String? napcatQrImagePath(String payload) {
  if (!payload.startsWith('file:')) return null;
  final value = payload.substring('file:'.length);
  final versionSeparator = value.lastIndexOf('#');
  return versionSeparator > 0 ? value.substring(0, versionSeparator) : value;
}

/// 绕过 FileImage 的路径缓存，直接读取当前二维码文件内容。
Uint8List napcatQrImageBytes(String payload) {
  final path = napcatQrImagePath(payload);
  if (path == null) throw ArgumentError.value(payload, 'payload');
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
  });

  final String path;
  final String cacheKey;
  final Color errorColor;

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
      width: 220,
      height: 220,
      fit: BoxFit.contain,
      gaplessPlayback: false,
      errorBuilder: (_, __, ___) => _errorView(),
    );
  }

  Widget _errorView() => SizedBox(
        width: 220,
        height: 220,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: widget.errorColor,
            size: 40,
          ),
        ),
      );
}
