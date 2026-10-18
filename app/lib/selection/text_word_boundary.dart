import 'package:flutter/painting.dart';

final _whitespace = RegExp(r'^\s$', unicode: true);
final _wordCharacter = RegExp(r'^[\p{L}\p{M}\p{N}_]$', unicode: true);

/// Returns the Unicode word boundary containing [codePointOffset].
///
/// Flutter reports UTF-16 code-unit offsets while OCR selection uses Unicode
/// code-point offsets, so both sides of the boundary are converted here.
({int start, int end})? textWordBoundary(String text, int codePointOffset) {
  final codePoints = text.runes.toList(growable: false);
  if (codePointOffset < 0 || codePointOffset >= codePoints.length) {
    return null;
  }

  final codeUnitOffset = String.fromCharCodes(codePoints.take(codePointOffset))
      .length;
  final painter = TextPainter(
    text: TextSpan(text: text),
    textDirection: TextDirection.ltr,
  )..layout();
  final boundary = painter.getWordBoundary(
    TextPosition(offset: codeUnitOffset),
  );
  painter.dispose();

  final result = (
    start: text.substring(0, boundary.start).runes.length,
    end: text.substring(0, boundary.end).runes.length,
  );

  final clicked = String.fromCharCode(codePoints[codePointOffset]);
  final kind = _whitespace.hasMatch(clicked)
      ? _CharacterKind.whitespace
      : _wordCharacter.hasMatch(clicked)
      ? _CharacterKind.word
      : _CharacterKind.punctuation;
  if (kind == _CharacterKind.word ||
      (kind == _CharacterKind.punctuation && result.end - result.start > 1)) {
    return result;
  }

  var start = codePointOffset;
  while (start > 0 && _kindOf(codePoints[start - 1]) == kind) {
    start--;
  }
  var end = codePointOffset + 1;
  while (end < codePoints.length && _kindOf(codePoints[end]) == kind) {
    end++;
  }
  return (start: start, end: end);
}

_CharacterKind _kindOf(int codePoint) {
  final character = String.fromCharCode(codePoint);
  if (_whitespace.hasMatch(character)) {
    return _CharacterKind.whitespace;
  }
  return _wordCharacter.hasMatch(character)
      ? _CharacterKind.word
      : _CharacterKind.punctuation;
}

enum _CharacterKind { word, whitespace, punctuation }

/// Code-point offset one word to the right of [offset] in [text]: skips
/// spaces, then runs to the end of the word (or punctuation run). Returns
/// null when only spaces remain.
({int start, int end})? nextWordAfter(String text, int offset) {
  final codePoints = text.runes.toList(growable: false);
  var start = offset < 0 ? 0 : offset;
  while (start < codePoints.length &&
      _kindOf(codePoints[start]) == _CharacterKind.whitespace) {
    start++;
  }
  if (start >= codePoints.length) {
    return null;
  }
  final kind = _kindOf(codePoints[start]);
  var end = start + 1;
  while (end < codePoints.length && _kindOf(codePoints[end]) == kind) {
    end++;
  }
  return (start: start, end: end);
}

/// The word to the left of [offset], mirror of [nextWordAfter].
({int start, int end})? previousWordBefore(String text, int offset) {
  final codePoints = text.runes.toList(growable: false);
  var end = offset > codePoints.length ? codePoints.length : offset;
  while (end > 0 && _kindOf(codePoints[end - 1]) == _CharacterKind.whitespace) {
    end--;
  }
  if (end <= 0) {
    return null;
  }
  final kind = _kindOf(codePoints[end - 1]);
  var start = end - 1;
  while (start > 0 && _kindOf(codePoints[start - 1]) == kind) {
    start--;
  }
  return (start: start, end: end);
}
