import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/detection/text_detectors.dart';

void main() {
  test('detects allowed web links, email addresses, and phone numbers', () {
    final detections = detectTextItems(
      'Visit https://example.com/a?q=1 or mail neo@example.dev, tel +1 555 0100',
    );

    expect(detections.map((item) => item.kind), [
      DetectedTextKind.link,
      DetectedTextKind.email,
      DetectedTextKind.phone,
    ]);
    expect(detections.first.target, 'https://example.com/a?q=1');
    expect(detections[1].target, 'mailto:neo@example.dev');
    expect(detections[2].target, 'tel:+15550100');
  });

  test('rejects unsafe link schemes', () {
    final detections = detectTextItems(
      'Ignore javascript:alert(1) and ftp://example.com but keep http://ok.test',
    );

    expect(detections, hasLength(1));
    expect(detections.single.target, 'http://ok.test');
  });
}
