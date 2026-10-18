import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/ui/motion/gnome_reduced_motion_port.dart';
import 'package:kiriglyph/ui/motion/motion_policy.dart';

void main() {
  test('unwraps the portal reply however many variants wrap it', () {
    const reduce = DBusString('reduce');
    expect(unwrapReducedMotion(reduce), 'reduce');
    expect(unwrapReducedMotion(const DBusVariant(reduce)), 'reduce');
    expect(
      unwrapReducedMotion(const DBusVariant(DBusVariant(reduce))),
      'reduce',
    );
    expect(unwrapReducedMotion(const DBusVariant(DBusBoolean(true))), isNull);
  });

  group('resolveMotionPolicy', () {
    test('is reduced when Flutter disables animations', () {
      expect(
        resolveMotionPolicy(disableAnimations: true, gnomeReducedMotion: null),
        MotionPolicy.reduced,
      );
    });

    test('is reduced when GNOME reduced-motion is reduce', () {
      expect(
        resolveMotionPolicy(
          disableAnimations: false,
          gnomeReducedMotion: 'reduce',
        ),
        MotionPolicy.reduced,
      );
    });

    test('is full when neither signal requests reduced motion', () {
      expect(
        resolveMotionPolicy(
          disableAnimations: false,
          gnomeReducedMotion: 'no-preference',
        ),
        MotionPolicy.full,
      );
    });
  });

  test('gnome read errors fail open to full motion', () async {
    final container = ProviderContainer(
      overrides: [
        gnomeReducedMotionPortProvider.overrideWithValue(_ThrowingGnomePort()),
      ],
    );
    addTearDown(container.dispose);

    final value = await container.read(gnomeReducedMotionProvider.future);
    expect(value, isNull);
    expect(container.read(motionPolicyProvider(false)), MotionPolicy.full);
  });

  test('glowEnabledProvider toggles in memory', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(glowEnabledProvider), isTrue);
    container.read(glowEnabledProvider.notifier).setEnabled(false);
    expect(container.read(glowEnabledProvider), isFalse);
  });
}

class _ThrowingGnomePort implements GnomeReducedMotionPort {
  @override
  Future<String?> readReducedMotion() => throw StateError('dbus unavailable');
}
