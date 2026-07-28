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
