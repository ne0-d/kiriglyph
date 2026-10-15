import 'package:flutter/foundation.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';

@immutable
class TextPosition {
  const TextPosition({required this.regionId, required this.offset});

  final String regionId;
  final int offset;
}

/// Immutable text-range selection over one OCR result.
///
/// Positions are line-local Unicode code-point boundaries. The anchor and
/// focus retain direction while reading and painting use their normalized
/// order.
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
      null,
      null,
    );
  }

  const RegionSelection._(
    this.regions,
    this._indexById,
    this._anchor,
    this._focus,
    this._lineAnchor,
    this._explicitRanges,
  );

  /// All regions in reading order.
  final List<TextRegion> regions;

  final Map<String, int> _indexById;
  final TextPosition? _anchor;
  final TextPosition? _focus;
  final int? _lineAnchor;
  final Map<String, (int, int)>? _explicitRanges;

  bool get hasSelection {
    final explicitRanges = _explicitRanges;
    if (explicitRanges != null) {
      return explicitRanges.values.any((range) => range.$1 < range.$2);
    }
    final anchor = _anchor;
    final focus = _focus;
    return anchor != null && focus != null && _compare(anchor, focus) != 0;
  }

  /// Zero-based reading-order position of [id], or null if unknown.
  int? indexOf(String id) => _indexById[id];

  bool isSelected(String id) {
    final index = _indexById[id];
    if (index == null) {
      return false;
    }
    final interval = _selectedInterval(index);
    return interval != null && interval.$1 < interval.$2;
  }

  /// Selected regions in reading order.
  List<TextRegion> get selectedRegions => [
    for (var index = 0; index < regions.length; index++)
      if (isSelected(regions[index].id)) regions[index],
  ];

  /// Plain text of the selected range, with newlines between source lines.
  String get selectedText {
    final explicitRanges = _explicitRanges;
    if (explicitRanges != null) {
      final pieces = <String>[];
      for (final region in regions) {
        final range = explicitRanges[region.id];
        if (range == null || range.$1 >= range.$2) {
          continue;
        }
        final codePoints = region.text.runes.toList(growable: false);
        pieces.add(
          String.fromCharCodes(codePoints.sublist(range.$1, range.$2)),
        );
      }
      return pieces.join('\n');
    }
    final endpoints = _normalized;
    if (endpoints == null) {
      return '';
    }
    final (lower, upper) = endpoints;
    final lowerIndex = _indexById[lower.regionId]!;
    final upperIndex = _indexById[upper.regionId]!;
    final pieces = <String>[];
    for (var index = lowerIndex; index <= upperIndex; index++) {
      final codePoints = regions[index].text.runes.toList(growable: false);
      final start = index == lowerIndex ? lower.offset : 0;
      final end = index == upperIndex ? upper.offset : codePoints.length;
      pieces.add(String.fromCharCodes(codePoints.sublist(start, end)));
    }
    return pieces.join('\n');
  }

  /// Plain text of every line, one per line, in reading order.
  String get allText => _join(regions);

  int get selectedCharacterCount => selectedText.runes.length;

  /// Replaces the selection with the single region [id].
  RegionSelection select(String id) {
    final index = _indexById[id];
    if (index == null) {
      return this;
    }
    return RegionSelection._(
      regions,
      _indexById,
      TextPosition(regionId: id, offset: 0),
      TextPosition(regionId: id, offset: _length(index)),
      index,
      null,
    );
  }

  /// Extends the selection from the current anchor to [id]. Without an
  /// anchor this behaves like [select].
  RegionSelection extendTo(String id) {
    final index = _indexById[id];
    if (index == null) {
      return this;
    }
    final anchorIndex = _lineAnchor;
    if (anchorIndex == null) {
      return select(id);
    }
    final anchorRegion = regions[anchorIndex];
    if (index < anchorIndex) {
      return RegionSelection._(
        regions,
        _indexById,
        TextPosition(regionId: anchorRegion.id, offset: _length(anchorIndex)),
        TextPosition(regionId: id, offset: 0),
        anchorIndex,
        null,
      );
    }
    return RegionSelection._(
      regions,
      _indexById,
      TextPosition(regionId: anchorRegion.id, offset: 0),
      TextPosition(regionId: id, offset: _length(index)),
      anchorIndex,
      null,
    );
  }

  /// Replaces the selection with one recognized character.
  RegionSelection selectCharacter(String regionId, int offset) {
    final index = _indexById[regionId];
    if (index == null || offset < 0 || offset >= _length(index)) {
      return this;
    }
    return selectRange(regionId, offset, offset + 1);
  }

  /// Replaces the selection with one validated range in [regionId].
  RegionSelection selectRange(String regionId, int start, int end) {
    final index = _indexById[regionId];
    if (index == null || start < 0 || start >= end || end > _length(index)) {
      return this;
    }
    return RegionSelection._(
      regions,
      _indexById,
      TextPosition(regionId: regionId, offset: start),
      TextPosition(regionId: regionId, offset: end),
      null,
      null,
    );
  }

  /// Replaces the selection with explicit per-line ranges.
  ///
  /// Used by freehand selection, where lines without matched characters must
  /// stay unselected even when they sit between selected lines in reading
  /// order.
  RegionSelection selectLineRanges(Map<String, (int, int)> ranges) {
    final validated = <String, (int, int)>{};
    TextPosition? first;
    TextPosition? last;
    for (final region in regions) {
      final range = ranges[region.id];
      final index = _indexById[region.id]!;
      if (range == null ||
          range.$1 < 0 ||
          range.$1 >= range.$2 ||
          range.$2 > _length(index)) {
        continue;
      }
      validated[region.id] = range;
      first ??= TextPosition(regionId: region.id, offset: range.$1);
      last = TextPosition(regionId: region.id, offset: range.$2);
    }
    if (validated.isEmpty || first == null || last == null) {
      return clear();
    }
    return RegionSelection._(
      regions,
      _indexById,
      first,
      last,
      null,
      Map.unmodifiable(validated),
    );
  }

  /// Starts an anchored drag at a validated text boundary.
  RegionSelection startAt(TextPosition position) {
    if (!_isValidPosition(position)) {
      return this;
    }
    return RegionSelection._(
      regions,
      _indexById,
      position,
      position,
      null,
      null,
    );
  }

  /// Moves the active boundary while preserving the drag anchor.
  RegionSelection extendToPosition(TextPosition position) {
    if (!_isValidPosition(position)) {
      return this;
    }
    final anchor = _anchor;
    if (anchor == null) {
      return startAt(position);
    }
    return RegionSelection._(regions, _indexById, anchor, position, null, null);
  }

  bool isRangeSelected(String regionId, int start, int end) {
    final index = _indexById[regionId];
    if (index == null || start >= end) {
      return false;
    }
    final interval = _selectedInterval(index);
    return interval != null && start < interval.$2 && end > interval.$1;
  }

  (int, int)? selectedRangeFor(String regionId) {
    final index = _indexById[regionId];
    return index == null ? null : _selectedInterval(index);
  }

  RegionSelection selectAll() {
    if (regions.isEmpty) {
      return this;
    }
    return RegionSelection._(
      regions,
      _indexById,
      TextPosition(regionId: regions.first.id, offset: 0),
      TextPosition(
        regionId: regions.last.id,
        offset: _length(regions.length - 1),
      ),
      null,
      null,
    );
  }

  RegionSelection moveHorizontal(int direction, {required bool extend}) {
    if (direction == 0 || regions.isEmpty) {
      return this;
    }
    if (!hasSelection) {
      return direction > 0 ? _selectFirstAvailable() : _selectLastAvailable();
    }
    if (extend) {
      final next = _stepBoundary(_focus!, direction);
      return next == null ? this : extendToPosition(next);
    }
    final endpoints = _selectionBounds!;
    final character = direction > 0
        ? _characterAtOrAfter(endpoints.$2)
        : _characterBefore(endpoints.$1);
    return character == null
        ? this
        : selectCharacter(character.regionId, character.offset);
  }

  RegionSelection moveVertical(int direction, {required bool extend}) {
    if (direction == 0 || regions.isEmpty) {
      return this;
    }
    if (!hasSelection) {
      return direction > 0 ? _selectFirstAvailable() : _selectLastAvailable();
    }
    final source = _focus!;
    final sourceIndex = _indexById[source.regionId]!;
    for (
      var targetIndex = sourceIndex + direction;
      targetIndex >= 0 && targetIndex < regions.length;
      targetIndex += direction
    ) {
      final length = _length(targetIndex);
      if (length == 0) {
        continue;
      }
      final targetOffset = extend
          ? source.offset.clamp(0, length)
          : source.offset.clamp(0, length - 1);
      final target = TextPosition(
        regionId: regions[targetIndex].id,
        offset: targetOffset,
      );
      return extend
          ? extendToPosition(target)
          : selectCharacter(target.regionId, target.offset);
    }
    return this;
  }

  /// Removes the selection.
  RegionSelection clear() =>
      RegionSelection._(regions, _indexById, null, null, null, null);

  (TextPosition, TextPosition)? get _normalized {
    final anchor = _anchor;
    final focus = _focus;
    if (anchor == null || focus == null || _compare(anchor, focus) == 0) {
      return null;
    }
    return _compare(anchor, focus) <= 0 ? (anchor, focus) : (focus, anchor);
  }

  (TextPosition, TextPosition)? get _selectionBounds {
    final explicitRanges = _explicitRanges;
    if (explicitRanges == null) {
      return _normalized;
    }
    TextPosition? first;
    TextPosition? last;
    for (final region in regions) {
      final range = explicitRanges[region.id];
      if (range == null || range.$1 >= range.$2) {
        continue;
      }
      first ??= TextPosition(regionId: region.id, offset: range.$1);
      last = TextPosition(regionId: region.id, offset: range.$2);
    }
    return first == null || last == null ? null : (first, last);
  }

  (int, int)? _selectedInterval(int index) {
    final explicitRanges = _explicitRanges;
    if (explicitRanges != null) {
      final range = explicitRanges[regions[index].id];
      return range == null ? null : (range.$1, range.$2);
    }
    final endpoints = _normalized;
    if (endpoints == null) {
      return null;
    }
    final (lower, upper) = endpoints;
    final lowerIndex = _indexById[lower.regionId]!;
    final upperIndex = _indexById[upper.regionId]!;
    if (index < lowerIndex || index > upperIndex) {
      return null;
    }
    final start = index == lowerIndex ? lower.offset : 0;
    final end = index == upperIndex ? upper.offset : _length(index);
    return (start, end);
  }

  int _compare(TextPosition first, TextPosition second) {
    final byLine = _indexById[first.regionId]!.compareTo(
      _indexById[second.regionId]!,
    );
    return byLine != 0 ? byLine : first.offset.compareTo(second.offset);
  }

  bool _isValidPosition(TextPosition position) {
    final index = _indexById[position.regionId];
    return index != null &&
        position.offset >= 0 &&
        position.offset <= _length(index);
  }

  int _length(int index) => regions[index].text.runes.length;

  TextPosition? _stepBoundary(TextPosition position, int direction) {
    final index = _indexById[position.regionId]!;
    if (direction > 0) {
      if (position.offset < _length(index)) {
        return TextPosition(
          regionId: position.regionId,
          offset: position.offset + 1,
        );
      }
      if (index + 1 < regions.length) {
        return TextPosition(regionId: regions[index + 1].id, offset: 0);
      }
      return null;
    }
    if (position.offset > 0) {
      return TextPosition(
        regionId: position.regionId,
        offset: position.offset - 1,
      );
    }
    if (index > 0) {
      return TextPosition(
        regionId: regions[index - 1].id,
        offset: _length(index - 1),
      );
    }
    return null;
  }

  TextPosition? _characterAtOrAfter(TextPosition position) {
    final index = _indexById[position.regionId]!;
    if (position.offset < _length(index)) {
      return position;
    }
    for (var next = index + 1; next < regions.length; next++) {
      if (_length(next) > 0) {
        return TextPosition(regionId: regions[next].id, offset: 0);
      }
    }
    return null;
  }

  TextPosition? _characterBefore(TextPosition position) {
    final index = _indexById[position.regionId]!;
    if (position.offset > 0) {
      return TextPosition(
        regionId: position.regionId,
        offset: position.offset - 1,
      );
    }
    for (var previous = index - 1; previous >= 0; previous--) {
      if (_length(previous) > 0) {
        return TextPosition(
          regionId: regions[previous].id,
          offset: _length(previous) - 1,
        );
      }
    }
    return null;
  }

  RegionSelection _selectFirstAvailable() {
    for (final region in regions) {
      if (region.text.runes.isNotEmpty) {
        return selectCharacter(region.id, 0);
      }
    }
    return this;
  }

  RegionSelection _selectLastAvailable() {
    for (final region in regions.reversed) {
      final length = region.text.runes.length;
      if (length > 0) {
        return selectCharacter(region.id, length - 1);
      }
    }
    return this;
  }

  static String _join(List<TextRegion> regions) =>
      regions.map((region) => region.text).join('\n');
}
