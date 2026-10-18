import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Map<String, ToolbarSessionPlacement> build() => {};

  ToolbarSessionPlacement forDisplay(String key) =>
      state[key] ?? const ToolbarSessionPlacement();

  void updateDisplay(String key, ToolbarSessionPlacement placement) {
    state = {...state, key: placement};
  }
}
