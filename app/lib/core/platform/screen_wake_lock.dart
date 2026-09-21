import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mofox_android/core/platform/platform_gateway.dart';
import 'package:mofox_android/core/utils/app_logger.dart';

/// Keeps the current Android window awake while critical long-running work is
/// active.
///
/// The controller is reference counted so overlapping operations cannot clear
/// `FLAG_KEEP_SCREEN_ON` while another operation still needs it. Platform
/// failures are deliberately best-effort and never fail the protected task.
class ScreenWakeLockController {
  ScreenWakeLockController(this._platform);

  final PlatformGateway _platform;
  int _holders = 0;
  Future<void> _transition = Future<void>.value();

  Future<T> keepAwakeWhile<T>(Future<T> Function() operation) async {
    await acquire();
    try {
      return await operation();
    } finally {
      await release();
    }
  }

  Future<void> acquire() async {
    _holders += 1;
    if (_holders == 1) {
      _transition = _transition.then((_) => _setEnabled(true));
    }
    await _transition;
  }

  Future<void> release() async {
    if (_holders == 0) return;
    _holders -= 1;
    if (_holders == 0) {
      _transition = _transition.then((_) => _setEnabled(false));
    }
    await _transition;
  }

  Future<void> releaseAll() async {
    if (_holders == 0) return;
    _holders = 0;
    _transition = _transition.then((_) => _setEnabled(false));
    await _transition;
  }

  Future<void> _setEnabled(bool enabled) async {
    try {
      await _platform.setKeepScreenOn(enabled: enabled);
    } on Object catch (error) {
      appLogger.w(
        'screen-wake-lock: failed to set enabled=$enabled: $error',
      );
    }
  }
}

final screenWakeLockProvider = Provider<ScreenWakeLockController>((ref) {
  final controller = ScreenWakeLockController(
    ref.watch(platformGatewayProvider),
  );
  ref.onDispose(() => unawaited(controller.releaseAll()));
  return controller;
});

/// Acquires a screen wake-lock lease for exactly as long as [child] is mounted.
class ScreenWakeLockScope extends ConsumerStatefulWidget {
  const ScreenWakeLockScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ScreenWakeLockScope> createState() =>
      _ScreenWakeLockScopeState();
}

class _ScreenWakeLockScopeState extends ConsumerState<ScreenWakeLockScope> {
  late final ScreenWakeLockController _controller;
  bool _acquired = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(screenWakeLockProvider);
    unawaited(_acquire());
  }

  Future<void> _acquire() async {
    await _controller.acquire();
    if (!mounted) {
      await _controller.release();
      return;
    }
    _acquired = true;
  }

  @override
  void dispose() {
    if (_acquired) unawaited(_controller.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
