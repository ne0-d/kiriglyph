import 'package:flutter_test/flutter_test.dart';

import 'package:ubuntu_live_text/selection/text_word_boundary.dart';

void main() {
  test('uses Unicode words and contiguous punctuation or whitespace runs', () {
    const text = 'one,,  two!';

    expect(textWordBoundary(text, 3), (start: 3, end: 5));
    expect(textWordBoundary(text, 5), (start: 5, end: 7));
    expect(textWordBoundary(text, 8), (start: 7, end: 10));
  });
}
