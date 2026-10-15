import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/diagnostics/timing_log.dart';

class _FakeClock implements TimingClock {
  int micros = 0;

  @override
  int nowMicros() => micros;

  void advanceMs(num milliseconds) {
    micros += (milliseconds * 1000).round();
  }
}

class _MemorySink implements TimingSink {
  final lines = <String>[];

  @override
  void appendLine(String line) => lines.add(line);
}

void main() {
  test('is disabled when no timing environment variable is set', () {
    final log = TimingLog.fromEnvironment(const {});

    log.beginActivation();
    log.mark(TimingPhase.capture);
    log.finish(TimingOutcome.dismissed);

    expect(log.enabled, isFalse);
  });

  test('writes only phase durations and allowlisted outcomes', () {
    final clock = _FakeClock();
    final sink = _MemorySink();
    final log = TimingLog(clock: clock, sink: sink);

    log.beginActivation();
    clock.advanceMs(120);
    log.mark(TimingPhase.capture);
    clock.advanceMs(30);
    log.mark(TimingPhase.crop);
    log.setDisplay(count: 2, scale: 1.25);
    clock.advanceMs(80);
    log.finish(TimingOutcome.dismissed);

    expect(sink.lines, hasLength(1));
    final payload = jsonDecode(sink.lines.single) as Map<String, Object?>;
    expect(payload['outcome'], 'dismissed');
    expect(payload['display_count'], 2);
    expect(payload['display_scale'], 1.25);
    expect(payload['phases'], {
      'shortcut_received_ms': 0.0,
      'capture_ms': 120.0,
      'crop_ms': 30.0,
    });
  });

  test('rejects non-allowlisted keys and string values', () {
    expect(
      () => validateTimingPayload({
        'schema': 1,
        'outcome': 'dismissed',
        'path': '/tmp/private.png',
        'phases': const <String, double>{},
      }),
      throwsStateError,
    );
    expect(
      () => validateTimingPayload({
        'schema': 1,
        'outcome': 'dismissed',
        'phases': {'capture_ms': '120'},
      }),
      throwsStateError,
    );
    expect(
      () => validateTimingPayload({
        'schema': 1,
        'outcome': 'contains_private_text',
        'phases': const <String, double>{},
      }),
      throwsStateError,
    );
  });
}
