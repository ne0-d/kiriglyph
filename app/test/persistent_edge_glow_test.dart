import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ui/motion/motion_policy.dart';
import 'package:kiriglyph/ui/overlay/persistent_edge_glow.dart';

void main() {
  testWidgets('persistent glow is hidden when disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersistentEdgeGlow(
            busy: true,
            policy: MotionPolicy.full,
            enabled: false,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('overlay-persistent-edge-glow')), findsNothing);
  });

  testWidgets('persistent glow stays static under reduced motion while busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersistentEdgeGlow(
            busy: true,
            policy: MotionPolicy.reduced,
            enabled: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('overlay-persistent-edge-glow')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
