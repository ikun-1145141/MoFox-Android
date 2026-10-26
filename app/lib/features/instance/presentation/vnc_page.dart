import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';

/// 虚拟屏幕页：截图轮询 + 触控注入。
///
/// 基于已验证的 snowlumaScreenshot + virtualTouch 管线。
/// 不是 VNC 实时流——是快速截图轮询（触控模式下 1s 间隔）。
class VncPage extends ConsumerStatefulWidget {
  const VncPage({required this.instanceId, super.key});

  final String instanceId;

  @override
  ConsumerState<VncPage> createState() => _VncPageState();
}

class _VncPageState extends ConsumerState<VncPage> {
  bool _touchMode = false;
  String? _screenshotPayload;
  Timer? _refreshTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startRefresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      _touchMode ? const Duration(seconds: 1) : const Duration(seconds: 3),
      (_) => _captureScreen(),
    );
    _captureScreen();
  }

  Future<void> _captureScreen() async {
    if (_disposed) return;
    final console = ref.read(processConsoleProvider.notifier);
    await console.refreshManualScreen();
    if (_disposed) return;
    final payload = ref.read(processConsoleProvider).snowlumaManualPayload;
    if (payload != null && payload != _screenshotPayload) {
      setState(() => _screenshotPayload = payload);
    }
  }

  Future<void> _handleTap(Offset localPosition, Size widgetSize) async {
    if (!_touchMode) return;
    final console = ref.read(processConsoleProvider.notifier);
    final frame = ref.read(processConsoleProvider).snowlumaManualPayload;
    if (frame == null) return;
    // 坐标换算：截图中 QQ 窗口占 800x600 虚拟屏幕
    // 截图显示尺寸 → 800x600 坐标 → virtualTouch
    final dx = localPosition.dx / widgetSize.width * 800;
    final dy = localPosition.dy / widgetSize.height * 600;
    await console.touchVirtualScreen(
      dx: dx.clamp(0, 799),
      dy: dy.clamp(0, 599),
      boxWidth: widgetSize.width,
    );
  }

  Future<void> _quickLogin() async {
    await ref.read(processConsoleProvider.notifier).quickLoginQq();
  }

  @override
  Widget build(BuildContext context) {
    final console = ref.watch(processConsoleProvider);
    final snowlumaRunning = console.snowlumaStatusFor(widget.instanceId) == 'running';
    final payload = console.snowlumaManualPayload ?? _screenshotPayload;

    return Scaffold(
      appBar: AppBar(
        title: const Text('虚拟屏幕'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新画面',
            icon: const Icon(Icons.refresh),
            onPressed: _captureScreen,
          ),
        ],
      ),
      body: !snowlumaRunning
          ? _MessagePane(
              icon: Icons.stop_circle_outlined,
              title: 'SnowLuma 未运行',
              message: '启动实例后，虚拟屏幕会自动显示。',
            )
          : Column(
              children: <Widget>[
                // 状态条
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 6,
                  ),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _touchMode
                            ? Icons.touch_app
                            : Icons.remove_red_eye_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _touchMode ? '触控模式（点按=左键）' : '查看模式',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        '800×600',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                      ),
                    ],
                  ),
                ),
                // 画面区域
                Expanded(
                  child: payload != null
                      ? _ScreenshotView(
                          payload: payload,
                          touchMode: _touchMode,
                          onTap: _handleTap,
                        )
                      : const Center(
                          child: CircularProgressIndicator(),
                        ),
                ),
                // 触控开关
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      FilterChip(
                        selected: _touchMode,
                        label: Text(_touchMode ? '触控：开' : '触控：关'),
                        avatar: Icon(
                          _touchMode ? Icons.touch_app : Icons.touch_app_outlined,
                          size: 18,
                        ),
                        onSelected: (value) {
                          setState(() => _touchMode = value);
                          _startRefresh(); // 切换刷新频率
                        },
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.tonalIcon(
                        onPressed: _quickLogin,
                        icon: const Icon(Icons.login_outlined),
                        label: const Text('快捷登录'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
  );
  }
}

/// 截图显示区域。
class _ScreenshotView extends StatelessWidget {
  const _ScreenshotView({
    required this.payload,
    required this.touchMode,
    required this.onTap,
  });

  final String payload;
  final bool touchMode;
  final Future<void> Function(Offset, Size) onTap;

  @override
  Widget build(BuildContext context) {
    // payload 格式: file:<host_path>#<version>
    final path = payload.split('#').first.replaceFirst('file:', '');
    return Center(
      child: GestureDetector(
        onTapUp: touchMode
            ? (details) {
                final box = context.findRenderObject() as RenderBox;
                onTap(details.localPosition, box.size);
              }
            : null,
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(
              color: touchMode
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outlineVariant,
              width: touchMode ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              cacheWidth: 1200,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Center(
                child: Text('等待画面…'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 消息面板。
class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
