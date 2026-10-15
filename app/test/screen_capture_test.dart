import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/capture/screen_capture.dart';

void main() {
  group('parseScreenCaptureOutput', () {
    test('parses a captured outcome with an absolute path', () {
      final capture = parseScreenCaptureOutput(
        '{"outcome":"captured","path":"/home/u/Pictures/Screenshot.png"}\n',
      );
      expect(capture.status, ScreenCaptureStatus.captured);
      expect(capture.path, '/home/u/Pictures/Screenshot.png');
    });

    test('maps every non-captured outcome without a path', () {
      const expected = {
        'cancelled': ScreenCaptureStatus.cancelled,
        'ended': ScreenCaptureStatus.ended,
        'unavailable': ScreenCaptureStatus.unavailable,
        'denied': ScreenCaptureStatus.denied,
        'invalid_uri': ScreenCaptureStatus.invalidUri,
        'unreadable': ScreenCaptureStatus.unreadable,
        'something_else': ScreenCaptureStatus.failed,
      };
      for (final entry in expected.entries) {
        final capture = parseScreenCaptureOutput(
          '{"outcome":"${entry.key}","path":"/tmp/ignored.png"}',
        );
        expect(capture.status, entry.value, reason: entry.key);
        expect(capture.path, isNull, reason: entry.key);
      }
    });

    test('treats cancelled and ended as neutral', () {
      expect(
        const ScreenCapture(ScreenCaptureStatus.cancelled).isNeutral,
        true,
      );
      expect(const ScreenCapture(ScreenCaptureStatus.ended).isNeutral, true);
      expect(const ScreenCapture(ScreenCaptureStatus.denied).isNeutral, false);
    });

    test('rejects a captured outcome without an absolute path', () {
      for (final line in [
        '{"outcome":"captured"}',
        '{"outcome":"captured","path":"relative.png"}',
        '{"outcome":"captured","path":42}',
      ]) {
        expect(
          parseScreenCaptureOutput(line).status,
          ScreenCaptureStatus.invalidUri,
          reason: line,
        );
      }
    });

    test('fails on empty, multi-line, malformed, or non-object output', () {
      for (final output in [
        '',
        '\n  \n',
        '{"outcome":"captured","path":"/a.png"}\n{"outcome":"ended"}',
        'not json',
        '["captured"]',
      ]) {
        expect(
          parseScreenCaptureOutput(output).status,
          ScreenCaptureStatus.failed,
          reason: output,
        );
      }
    });
  });
}
