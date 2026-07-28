import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/selection/region_selection.dart';
import 'package:ubuntu_live_text/selection/text_word_boundary.dart';

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

  void selectCharacter(String regionId, int offset) =>
      state = state.selectCharacter(regionId, offset);

  void selectWord(String regionId, int offset) {
    final index = state.indexOf(regionId);
    if (index == null) {
      return;
    }
    final boundary = textWordBoundary(state.regions[index].text, offset);
    if (boundary != null) {
      state = state.selectRange(regionId, boundary.start, boundary.end);
    }
  }

  void startAt(TextPosition position) => state = state.startAt(position);

  void extendToPosition(TextPosition position) =>
      state = state.extendToPosition(position);

  void selectAll() => state = state.selectAll();

  void moveHorizontal(int direction, {required bool extend}) =>
      state = state.moveHorizontal(direction, extend: extend);

  void moveVertical(int direction, {required bool extend}) =>
      state = state.moveVertical(direction, extend: extend);

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

class CopySelectionRequestController extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final copySelectionRequestProvider =
    NotifierProvider<CopySelectionRequestController, int>(
      CopySelectionRequestController.new,
    );
