import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

/// 单个粒子的状态。
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
  });

  double x;
  double y;
  double vx;
  double vy;
  final Color color;
  final double size;
  double life = 1.0; // 1 → 0
}

/// 爆炸粒子覆盖层。
///
/// 在 [Overlay] 中插入，在 [rect] 区域内生成粒子向四周飞散，
/// 持续 [duration] 后自动移除。
class ExplosionOverlay extends StatefulWidget {
  const ExplosionOverlay({
    required this.rect,
    required this.color,
    super.key,
    this.duration = const Duration(milliseconds: 800),
    this.particleCount = 28,
    this.onCompleted,
  });

  /// 爆炸中心区域（屏幕坐标）。
  final Rect rect;

  /// 粒子主色调。
  final Color color;

  /// 动画总时长。
  final Duration duration;

  /// 粒子数量。
  final int particleCount;

  /// 在 [overlay] 上插入一个爆炸动画，动画结束后自动移除。
  static void show(
    BuildContext context, {
    required Rect rect,
    required Color color,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ExplosionOverlay(
        rect: rect,
        color: color,
        onCompleted: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  /// 仅用于 [show] 回调。
  final VoidCallback? onCompleted;

  @override
  State<ExplosionOverlay> createState() => _ExplosionOverlayState();
}

class _ExplosionOverlayState extends State<ExplosionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  late final Color _particleColor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onCompleted?.call();
        }
      });

    _particleColor = widget.color;
    _particles = _generateParticles();

    _controller.forward();
  }

  List<_Particle> _generateParticles() {
    final random = Random();
    final cx = widget.rect.center.dx;
    final cy = widget.rect.center.dy;
    return List.generate(widget.particleCount, (_) {
      final angle = random.nextDouble() * 2 * pi;
      // 速度 80–280 px/s（按 1 秒寿命缩放）
      final speed = 80 + random.nextDouble() * 200;
      return _Particle(
        x: cx + (random.nextDouble() - 0.5) * widget.rect.width * 0.3,
        y: cy + (random.nextDouble() - 0.5) * widget.rect.height * 0.3,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 40, // 略微向上偏移
        color: _particleColor,
        size: 3 + random.nextDouble() * 5,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return CustomPaint(
          painter: _ExplosionPainter(
            particles: _particles,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ExplosionPainter extends CustomPainter {
  _ExplosionPainter({
    required this.particles,
    required this.progress,
  });

  final List<_Particle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final dt = progress; // 0 → 1
    for (final p in particles) {
      // 重力 + 阻尼
      final gravity = 300 * dt * dt;
      final px = p.x + p.vx * dt;
      final py = p.y + p.vy * dt + gravity;
      final alpha = (1 - dt).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(px, py), p.size * (1 - dt * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ExplosionPainter oldDelegate) => true;
}
