import 'package:flutter/animation.dart';

import 'package:kiriglyph/ui/motion/motion_policy.dart';

/// Standard overlay transition durations (issue 25).
abstract final class AppMotionDurations {
  static const toolbar = Duration(milliseconds: 160);
  static const chip = Duration(milliseconds: 150);
  static const status = Duration(milliseconds: 120);
  static const strokeFade = Duration(milliseconds: 300);
}

Duration motionDuration(MotionPolicy policy, Duration full) {
  return policy == MotionPolicy.reduced ? Duration.zero : full;
}

Curve get motionCurve => Curves.easeOutCubic;
