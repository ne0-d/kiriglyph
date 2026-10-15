import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/protocol/worker_protocol.dart';
import 'package:kiriglyph/selection/paragraph_grouping.dart';

void main() {
  test('paragraph grouping matches the OCR corpus manifest where OCR lines exist', () {
    final path = Platform.environment['OCR_CORPUS_RESULTS'];
    if (path == null) {
      // ignore: avoid_print
      print('paragraph corpus eval skipped; set OCR_CORPUS_RESULTS');
      return;
    }
    final payload =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final cases = payload['cases'] as List<Object?>;
    var evaluated = 0;
    var exactMatches = 0;
    for (final rawCase in cases) {
      final item = rawCase as Map<String, Object?>;
      if (item['ok'] != true) {
        continue;
      }
      final result = parseSuccessResult(item['ocr_result']);
      final lineTexts = [for (final region in result.regions) region.text];
      final expectedTexts = [
        for (final line in item['expected_lines'] as List<Object?>)
          line! as String,
      ];
      final actual = [
        for (final paragraph in groupTextParagraphs(result.regions))
          [
            for (final id in paragraph.regionIds)
              int.parse(id.substring('line-'.length)) - 1,
          ],
      ];
      final expected = [
        for (final paragraph in item['paragraphs'] as List<Object?>)
          [for (final index in paragraph as List<Object?>) index as int],
      ];
      evaluated++;
      final exact = _sameParagraphs(actual, expected);
      if (exact) {
        exactMatches++;
      }
      // ignore: avoid_print
      print(
        'paragraph_case ${jsonEncode({'id': item['id'], 'classification': exact ? 'exact' : _classifyMismatch(expected, actual), 'expected': _describeGroups(expected, expectedTexts), 'actual': _describeGroups(actual, lineTexts)})}',
      );
    }
    final accuracy = evaluated == 0 ? 0 : exactMatches / evaluated;
    // Printed by flutter test and captured in the Python evidence report.
    // ignore: avoid_print
    print('paragraph_grouping_accuracy=$accuracy ($exactMatches/$evaluated)');
    // This is an evidence harness, not a product gate. Keep the assertion low
    // enough to catch a broken bridge while the report records real failures.
    expect(accuracy, greaterThanOrEqualTo(0.50));
  });
}

String _classifyMismatch(List<List<int>> expected, List<List<int>> actual) {
  final expectedByLine = _groupIndexByLine(expected);
  final actualByLine = _groupIndexByLine(actual);
  final hasMerge = actual.any((group) {
    final expectedGroups = {
      for (final line in group)
        if (expectedByLine.containsKey(line)) expectedByLine[line],
    };
    return expectedGroups.length > 1;
  });
  final hasSplit = expected.any((group) {
    final actualGroups = {
      for (final line in group)
        if (actualByLine.containsKey(line)) actualByLine[line],
    };
    return actualGroups.length > 1;
  });
  return switch ((hasMerge, hasSplit)) {
    (true, false) => 'merge',
    (false, true) => 'split',
    (false, false) => 'other',
    (true, true) => 'other',
  };
}

Map<int, int> _groupIndexByLine(List<List<int>> groups) => {
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex++)
    for (final line in groups[groupIndex]) line: groupIndex,
};

List<List<String>> _describeGroups(List<List<int>> groups, List<String> lines) {
  return [
    for (final group in groups)
      [
        for (final line in group)
          '$line:${_prefix(line >= 0 && line < lines.length ? lines[line] : '')}',
      ],
  ];
}

String _prefix(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final characters = normalized.runes.toList(growable: false);
  if (characters.length <= 30) {
    return normalized;
  }
  return String.fromCharCodes(characters.take(30));
}

bool _sameParagraphs(List<List<int>> left, List<List<int>> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index].length != right[index].length) {
      return false;
    }
    for (var inner = 0; inner < left[index].length; inner++) {
      if (left[index][inner] != right[index][inner]) {
        return false;
      }
    }
  }
  return true;
}
