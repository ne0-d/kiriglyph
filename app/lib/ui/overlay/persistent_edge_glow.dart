import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';

const _breathPeriod = Duration(milliseconds: 5000);
const _throttleInterval = Duration(milliseconds: 100);

/// Calm frame around the overlay for the whole session; breathes only while busy.
class PersistentEdgeGlow extends StatefulWidget {
  const PersistentEdgeGlow({
    super.key,
    required this.busy,
    required this.policy,
    required this.enabled,
  });

  final bool busy;
  final MotionPolicy policy;
  final bool enabled;

  @override
  State<PersistentEdgeGlow> createState() => _PersistentEdgeGlowState();
}

class _PersistentEdgeGlowState extends State<PersistentEdgeGlow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  Duration _lastTick = Duration.zero;
  double _breath = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!widget.enabled) {
      return;
    }
    if (elapsed - _lastTick < _throttleInterval) {
      return;
    }
    _lastTick = elapsed;
    if (widget.policy == MotionPolicy.reduced || !widget.busy) {
      if (_breath != 0) {
        setState(() => _breath = 0);
      }
      return;
    }
    _elapsed = elapsed;
    final phase =
        (_elapsed.inMicroseconds % _breathPeriod.inMicroseconds) /
        _breathPeriod.inMicroseconds;
    final next = math.sin(phase * 2 * math.pi) * 0.04;
    if ((next - _breath).abs() > 0.005) {
      setState(() => _breath = next);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('overlay-persistent-edge-glow'),
          size: Size.infinite,
          painter: PersistentEdgeGlowPainter(
            breath: widget.policy == MotionPolicy.reduced ? 0 : _breath,
            scheme: Theme.of(context).colorScheme,
          ),
        ),
      ),
    );
  }
}

class PersistentEdgeGlowPainter extends CustomPainter {
  const PersistentEdgeGlowPainter({required this.breath, required this.scheme});

  final double breath;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    // As wide as the entry glow you see when the overlay opens.
    final depth = math.min(size.shortestSide / 6, 40.0);
    final accent = Color.lerp(
      scheme.primary,
      AppColors.ubuntuOrange,
      0.7,
    )!.withValues(alpha: 0.5 + breath);
    final keyline = scheme.scrim.withValues(alpha: 0.72);
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
            // An eased fall-off reads as light, not as a hard band.
            colors: [
              accent,
              accent.withValues(alpha: accent.a * 0.35),
              accent.withValues(alpha: 0),
            ],
            stops: const [0, 0.4, 1],
          ).createShader(rect),
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = keyline,
    );
  }

  @override
  bool shouldRepaint(covariant PersistentEdgeGlowPainter oldDelegate) =>
      oldDelegate.breath != breath || oldDelegate.scheme != scheme;
}
