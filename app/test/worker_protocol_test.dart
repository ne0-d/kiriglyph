import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/protocol/worker_protocol.dart';

Map<String, Object> _singleRangePayload(Map<String, Object?> patch) => {
  'image': {'width': 100, 'height': 40},
  'full_text': 'a',
  'regions': [
    {
      'id': 'line-1',
      'level': 'line',
      'text': 'a',
      'polygon': [
        [0, 0],
        [20, 0],
        [20, 10],
        [0, 10],
      ],
      'confidence': 1,
      'reading_order': 0,
      'ranges': [
        {
          'start': 0,
          'end': 1,
          'text': 'a',
          'polygon': [
            [0, 0],
            [10, 0],
            [10, 10],
            [0, 10],
          ],
          'geometry_kind': 'derived_ctc_polygon',
          'confidence': 1,
          ...patch,
        },
      ],
    },
  ],
  'timings_ms': {'total': 0},
};

void main() {
  test('parseSuccessResult accepts contract-shaped payload', () {
    final result = parseSuccessResult({
      'image': {'width': 640, 'height': 480},
      'full_text': 'He',
      'regions': [
        {
          'id': 'line-1',
          'level': 'line',
          'text': 'He',
          'polygon': [
            [10, 20],
            [200, 20],
            [200, 40],
            [10, 40],
          ],
          'confidence': 1.0,
          'reading_order': 0,
          'ranges': [
            {
              'start': 0,
              'end': 1,
              'text': 'H',
              'polygon': [
                [10, 20],
                [20, 20],
                [20, 40],
                [10, 40],
              ],
              'geometry_kind': 'derived_ctc_polygon',
              'confidence': 0.9,
            },
            {
              'start': 1,
              'end': 2,
              'text': 'e',
              'polygon': [
                [20, 20],
                [30, 20],
                [30, 40],
                [20, 40],
              ],
              'geometry_kind': 'derived_ctc_polygon',
              'confidence': 0.8,
            },
          ],
        },
      ],
      'timings_ms': {'total': 0},
    });

    expect(result.imageWidth, 640);
    expect(result.fullText, 'He');
    expect(result.regions.single.id, 'line-1');
    expect(result.regions.single.ranges.first.text, 'H');
    expect(
      result.regions.single.ranges.first.geometryKind,
      CharacterGeometryKind.derivedCtcPolygon,
    );
  });

  test('parseSuccessResult rejects non-contiguous character ranges', () {
    final payload = {
      'image': {'width': 100, 'height': 40},
      'full_text': 'ab',
      'regions': [
        {
          'id': 'line-1',
          'level': 'line',
          'text': 'ab',
          'polygon': [
            [0, 0],
            [20, 0],
            [20, 10],
            [0, 10],
          ],
          'confidence': 1,
          'reading_order': 0,
          'ranges': [
            {
              'start': 1,
              'end': 2,
              'text': 'b',
              'polygon': [
                [10, 0],
                [20, 0],
                [20, 10],
                [10, 10],
              ],
              'geometry_kind': 'derived_ctc_polygon',
              'confidence': 1,
            },
          ],
        },
      ],
      'timings_ms': {'total': 0},
    };

    expect(
      () => parseSuccessResult(payload),
      throwsA(
        isA<ProtocolError>().having(
          (error) => error.message,
          'message',
          contains('contiguous'),
        ),
      ),
    );
  });

  for (final (name, patch) in [
    ('unknown provenance', <String, Object?>{'geometry_kind': 'estimated'}),
    ('invalid confidence', <String, Object?>{'confidence': 2}),
    (
      'out-of-image polygon',
      <String, Object?>{
        'polygon': [
          [-1, 0],
          [10, 0],
          [10, 10],
          [-1, 10],
        ],
      },
    ),
    ('extra field', <String, Object?>{'extra': true}),
  ]) {
    test('parseSuccessResult rejects $name in a character range', () {
      expect(
        () => parseSuccessResult(_singleRangePayload(patch)),
        throwsA(isA<ProtocolError>()),
      );
    });
  }

  test('parseResponseLine rejects id mismatch', () {
    const line =
        '{"version":1,"id":"a","ok":true,"result":{"image":{"width":1,"height":1},"full_text":"","regions":[{"id":"line-1","level":"line","text":"x","polygon":[[0,0],[1,0],[1,1],[0,1]],"confidence":1,"reading_order":0}],"timings_ms":{"total":0}}}';

    expect(
      () => parseResponseLine(line, expectedId: 'b'),
      throwsA(isA<ProtocolError>()),
    );
  });
}
