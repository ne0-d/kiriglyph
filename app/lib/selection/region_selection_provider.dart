import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/selection/region_selection.dart';

/// Line selection for the active capture session.
///
/// The selection is rebuilt from scratch whenever the session's OCR result
/// changes, so retrying, starting a new image, or opening another image never
/// carries a selection into the next session.
class RegionSelectionController extends Notifier<RegionSelection> {
  @override
  RegionSelection build() {
    final result = ref.watch(
      captureSessionProvider.select((session) => session.ocrResult),
    );
    return RegionSelection(result?.regions ?? const []);
  }

  void select(String id) => state = state.select(id);

  void extendTo(String id) => state = state.extendTo(id);

  void clear() => state = state.clear();

  /// Applies a pointer or keyboard activation: Shift extends, otherwise
  /// the activated line replaces the selection.
  void activate(String id, {required bool extend}) {
    if (extend) {
      extendTo(id);
    } else {
      select(id);
    }
  }
}

final regionSelectionProvider =
    NotifierProvider<RegionSelectionController, RegionSelection>(
      RegionSelectionController.new,
    );

/// The region id currently under the pointer, shared by the image canvas and
/// the text rows so hovering either highlights both.
class HoveredRegionController extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(captureSessionProvider.select((session) => session.ocrResult));
    return null;
  }

  void enter(String id) => state = id;

  void leave(String id) {
    if (state == id) {
      state = null;
    }
  }
}

final hoveredRegionProvider =
    NotifierProvider<HoveredRegionController, String?>(
      HoveredRegionController.new,
    );
