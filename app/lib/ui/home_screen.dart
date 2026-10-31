import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/window_surface.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/ui/overlay/presentable_transparency.dart';
import 'package:kiriglyph/ui/overlay/selection_overlay_screen.dart';
import 'package:kiriglyph/ui/settings/preferences_page.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(
      selectionOverlayProvider.select(
        (overlay) =>
            overlay.isActive && overlay.phase != OverlayPhase.capturing,
      ),
    );
    if (overlay) {
      return const SelectionOverlayScreen();
    }
    if (!ref.watch(mainWindowShownProvider)) {
      return const PresentableTransparency();
    }

    return const PreferencesPage();
  }
}
