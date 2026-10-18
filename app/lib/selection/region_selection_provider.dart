import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';
import 'package:kiriglyph/selection/region_selection.dart';
import 'package:kiriglyph/selection/text_word_boundary.dart';

/// The OCR result shown in the active selection overlay.
OcrResult? _watchActiveResult(Ref ref) {
  return ref.watch(
    selectionOverlayProvider.select((overlay) => overlay.ocrResult),
  );
}

/// Line selection for the active OCR result.
///
/// The selection is rebuilt from scratch whenever the active result changes,
/// so each new overlay session never carries a selection forward.
class RegionSelectionController extends Notifier<RegionSelection> {
  @override
  RegionSelection build() {
    final result = _watchActiveResult(ref);
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

  void selectLineRanges(Map<String, (int, int)> ranges) =>
      state = state.selectLineRanges(ranges);

  void startAt(TextPosition position) => state = state.startAt(position);

  void extendToPosition(TextPosition position) =>
      state = state.extendToPosition(position);

  void selectAll() => state = state.selectAll();

  void moveHorizontal(int direction, {required bool extend}) =>
      state = state.moveHorizontal(direction, extend: extend);

  void moveByWord(int direction, {required bool extend}) =>
      state = state.moveByWord(direction, extend: extend);

  void moveToLineEdge({required bool end, required bool extend}) =>
      state = state.moveToLineEdge(end: end, extend: extend);

  void moveVertical(int direction, {required bool extend}) =>
      state = state.moveVertical(direction, extend: extend);

  /// Keyboard selection by whole paragraphs: [direction] 1 is down.
  void extendByParagraph(List<TextParagraph> paragraphs, int direction) =>
      state = extendSelectionByParagraph(
        state,
        paragraphs,
        direction: direction,
      );

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
    _watchActiveResult(ref);
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
