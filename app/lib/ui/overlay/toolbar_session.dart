import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/overlay/toolbar_placement.dart';

/// In-memory toolbar placement per display for the resident session.
final toolbarSessionProvider =
    NotifierProvider<
      ToolbarSessionNotifier,
      Map<String, ToolbarSessionPlacement>
    >(ToolbarSessionNotifier.new);

class ToolbarSessionNotifier
    extends Notifier<Map<String, ToolbarSessionPlacement>> {
  @override
  Map<String, ToolbarSessionPlacement> build() {
    // Every new capture starts with the toolbar at the bottom centre, not
    // wherever it was dragged last time.
    ref.listen(selectionOverlayProvider.select((overlay) => overlay.isActive), (
      wasActive,
      isActive,
    ) {
      if (isActive && wasActive != true) {
        state = {};
      }
    });
    return {};
  }

  ToolbarSessionPlacement forDisplay(String key) =>
      state[key] ?? defaultToolbarSessionPlacement;

  void updateDisplay(String key, ToolbarSessionPlacement placement) {
    state = {...state, key: placement};
  }
}

/// Where the toolbar starts: bottom centre.
const defaultToolbarSessionPlacement = ToolbarSessionPlacement(
  mode: ToolbarAnchorMode.bottom,
);
