import 'package:flutter_test/flutter_test.dart';

import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/protocol/worker_protocol.dart';

void main() {
  test('parseSuccessResult accepts contract-shaped payload', () {
    final result = parseSuccessResult({
      'image': {'width': 640, 'height': 480},
      'full_text': 'Hello Live Text',
      'regions': [
        {
          'id': 'line-1',
          'level': 'line',
          'text': 'Hello Live Text',
          'polygon': [
            [10, 20],
            [200, 20],
            [200, 40],
            [10, 40],
          ],
          'confidence': 1.0,
          'reading_order': 0,
        },
      ],
      'timings_ms': {'total': 0},
    });

    expect(result.imageWidth, 640);
    expect(result.fullText, 'Hello Live Text');
    expect(result.regions.single.id, 'line-1');
  });

  test('parseResponseLine rejects id mismatch', () {
    const line =
        '{"version":1,"id":"a","ok":true,"result":{"image":{"width":1,"height":1},"full_text":"","regions":[{"id":"line-1","level":"line","text":"x","polygon":[[0,0],[1,0],[1,1],[0,1]],"confidence":1,"reading_order":0}],"timings_ms":{"total":0}}}';

    expect(
      () => parseResponseLine(line, expectedId: 'b'),
      throwsA(isA<ProtocolError>()),
    );
  });
}
