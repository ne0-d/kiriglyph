import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kiriglyph/theme/app_theme.dart';

const glowDuration = Duration(milliseconds: 900);
const _sweepPeriod = Duration(milliseconds: 1800);

/// The entry glow: picks up from GNOME's white capture flash at the display
/// edges, warms to Ubuntu orange, and fades out.
class EntryGlow extends StatelessWidget {
  const EntryGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: glowDuration,
        builder: (context, progress, _) => CustomPaint(
          key: const Key('overlay-entry-glow'),
          size: Size.infinite,
          painter: EdgeGlowPainter(progress),
        ),
      ),
    );
  }
}

class EdgeGlowPainter extends CustomPainter {
  const EdgeGlowPainter(this.progress);

  /// 0 at the flash, 1 when the glow has gone.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = progress < 0.25
        ? 1.0
        : 1 - Curves.easeOut.transform((progress - 0.25) / 0.75);
    if (strength <= 0 || size.isEmpty) {
      return;
    }
    final depth =
        math.min(size.shortestSide / 6, 40) *
        (0.35 + 0.65 * Curves.easeOut.transform(math.min(progress * 2, 1)));
    final color = Color.lerp(
      Colors.white,
      AppColors.ubuntuOrange,
      Curves.easeOut.transform(math.min(progress * 2.5, 1)),
    )!.withValues(alpha: 0.55 * strength);
    final edges = [
      (Rect.fromLTWH(0, 0, size.width, depth), Alignment.topCenter),
      (
        Rect.fromLTWH(0, size.height - depth, size.width, depth),
        Alignment.bottomCenter,
      ),
      (Rect.fromLTWH(0, 0, depth, size.height), Alignment.centerLeft),
      (
        Rect.fromLTWH(size.width - depth, 0, depth, size.height),
        Alignment.centerRight,
      ),
    ];
    for (final (rect, from) in edges) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: from,
            end: -from,
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant EdgeGlowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// A soft band sweeping across the frozen display while OCR runs.
class ScanSweep extends StatefulWidget {
  const ScanSweep({super.key});

  @override
  State<ScanSweep> createState() => _ScanSweepState();
}

class _ScanSweepState extends State<ScanSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _sweepPeriod,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          key: const Key('overlay-scan-sweep'),
          size: Size.infinite,
          painter: ScanSweepPainter(_controller.value),
        ),
      ),
    );
  }
}

class ScanSweepPainter extends CustomPainter {
  const ScanSweepPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final band = size.width * 0.18;
    final left =
        -band + (size.width + band) * Curves.easeInOut.transform(progress);
    final rect = Rect.fromLTWH(left, 0, band, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant ScanSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
