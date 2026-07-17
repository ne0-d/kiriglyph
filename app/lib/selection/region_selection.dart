import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';

/// Immutable line selection over one OCR result.
///
/// Regions are always held in reading order. A selection is a contiguous
/// range between a fixed anchor and a moving focus, which keeps replacement,
/// Shift-extension in either direction, and copy text deterministic.
@immutable
class RegionSelection {
  /// Creates an empty selection over [regions], ordering them by
  /// [TextRegion.readingOrder]. Ties keep their input order.
  factory RegionSelection(Iterable<TextRegion> regions) {
    final indexed = regions.toList().asMap().entries.toList()
      ..sort((a, b) {
        final byOrder = a.value.readingOrder.compareTo(b.value.readingOrder);
        return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
      });
    final ordered = List<TextRegion>.unmodifiable(
      indexed.map((entry) => entry.value),
    );
    return RegionSelection._(
      ordered,
      {for (var i = 0; i < ordered.length; i++) ordered[i].id: i},
      null,
      null,
    );
  }

  const RegionSelection._(
    this.regions,
    this._indexById,
    this._anchor,
    this._focus,
  );

  /// All regions in reading order.
  final List<TextRegion> regions;

  final Map<String, int> _indexById;
  final int? _anchor;
  final int? _focus;

  bool get hasSelection => _anchor != null && _focus != null;

  /// Zero-based reading-order position of [id], or null if unknown.
  int? indexOf(String id) => _indexById[id];

  bool isSelected(String id) {
    final index = _indexById[id];
    if (index == null || !hasSelection) {
      return false;
    }
    return index >= _lower && index <= _upper;
  }

  /// Selected regions in reading order.
  List<TextRegion> get selectedRegions =>
      hasSelection ? regions.sublist(_lower, _upper + 1) : const [];

  /// Plain text of the selected lines, one per line, in reading order.
  String get selectedText => _join(selectedRegions);

  /// Plain text of every line, one per line, in reading order.
  String get allText => _join(regions);

  /// Replaces the selection with the single region [id].
  RegionSelection select(String id) {
    final index = _indexById[id];
    if (index == null) {
      return this;
    }
    return RegionSelection._(regions, _indexById, index, index);
  }

  /// Extends the selection from the current anchor to [id]. Without an
  /// anchor this behaves like [select].
  RegionSelection extendTo(String id) {
    final index = _indexById[id];
    if (index == null) {
      return this;
    }
    final anchor = _anchor;
    if (anchor == null) {
      return select(id);
    }
    return RegionSelection._(regions, _indexById, anchor, index);
  }

  /// Removes the selection.
  RegionSelection clear() => RegionSelection._(regions, _indexById, null, null);

  int get _lower => math.min(_anchor!, _focus!);
  int get _upper => math.max(_anchor!, _focus!);

  static String _join(List<TextRegion> regions) =>
      regions.map((region) => region.text).join('\n');
}
