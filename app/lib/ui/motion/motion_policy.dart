import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/ui/motion/gnome_reduced_motion_port.dart';

/// Whether overlay motion runs at full speed or is minimized for accessibility.
enum MotionPolicy { full, reduced }

/// Pure resolution used by [motionPolicyProvider] and unit tests.
MotionPolicy resolveMotionPolicy({
  required bool disableAnimations,
  String? gnomeReducedMotion,
}) {
  if (disableAnimations) {
    return MotionPolicy.reduced;
  }
  if (gnomeReducedMotion == 'reduce') {
    return MotionPolicy.reduced;
  }
  return MotionPolicy.full;
}

final gnomeReducedMotionPortProvider = Provider<GnomeReducedMotionPort>(
  (ref) => PortalGnomeReducedMotionPort(),
);

/// Cached GNOME `reduced-motion` value; fails open to `null` (treat as full).
final gnomeReducedMotionProvider = FutureProvider<String?>((ref) async {
  try {
    return await ref.watch(gnomeReducedMotionPortProvider).readReducedMotion();
  } catch (_) {
    return null;
  }
});

/// Effective motion policy for the overlay chrome.
///
/// Pass [disableAnimations] from `MediaQuery.disableAnimationsOf(context)`.
/// GNOME is read once per provider scope; errors fail open to [MotionPolicy.full].
final motionPolicyProvider = Provider.family<MotionPolicy, bool>((
  ref,
  disableAnimations,
) {
  final gnome = ref
      .watch(gnomeReducedMotionProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
  return resolveMotionPolicy(
    disableAnimations: disableAnimations,
    gnomeReducedMotion: gnome,
  );
});

/// In-memory edge-glow toggle for this app session (persistent settings later).
final glowEnabledProvider = NotifierProvider<GlowEnabledNotifier, bool>(
  GlowEnabledNotifier.new,
);

class GlowEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;

  void toggle() => state = !state;
}
