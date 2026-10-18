import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TimingOutcome {
  ready,
  dismissed,
  failed,
  permissionRequired,
  copied,
  saved,
  cancelled,
}

enum TimingPhase {
  forward('forward_ms'),
  portal('portal_ms'),
  read('read_ms'),
  decode('decode_ms'),
  map('map_ms'),
  crop('crop_ms'),
  reveal('reveal_ms'),
  pngEncode('png_encode_ms'),
  ocrDispatch('ocr_dispatch_ms'),
  ocrResult('ocr_result_ms'),
  embed('embed_ms'),
  prompt('prompt_ms'),
  maskRender('mask_render_ms'),
  clipboard('clipboard_ms'),
  firstPaint('first_paint_ms');

  const TimingPhase(this.jsonKey);

  final String jsonKey;
}

abstract interface class TimingClock {
  int nowMicros();
}

class StopwatchTimingClock implements TimingClock {
  StopwatchTimingClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  int nowMicros() => _stopwatch.elapsedMicroseconds;
}

abstract interface class TimingSink {
  void appendLine(String line);
}

class FileTimingSink implements TimingSink {
  FileTimingSink(this.path);

  final String path;

  @override
  void appendLine(String line) {
    File(path).writeAsString('$line\n', mode: FileMode.append);
  }
}

class TimingLog {
  TimingLog({required TimingClock clock, TimingSink? sink})
    : this._(clock, sink);

  TimingLog._(this._clock, this._sink);

  factory TimingLog.fromEnvironment(Map<String, String> environment) {
    final raw = environment['KIRIGLYPH_TIMING_LOG'];
    if (raw == null || raw.isEmpty) {
      return TimingLog.disabled();
    }
    final path = raw == '1'
        ? '${environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path}/kiriglyph-timing.jsonl'
        : raw;
    return TimingLog(clock: StopwatchTimingClock(), sink: FileTimingSink(path));
  }

  factory TimingLog.disabled() =>
      TimingLog(clock: StopwatchTimingClock(), sink: null);

  final TimingClock _clock;
  final TimingSink? _sink;
  _TimingActivation? _active;

  bool get enabled => _sink != null;

  void beginActivation() {
    if (!enabled) {
      return;
    }
    final now = _clock.nowMicros();
    _active = _TimingActivation(startedMicros: now);
  }

  void mark(TimingPhase phase) {
    final active = _active;
    if (active == null) {
      return;
    }
    final now = _clock.nowMicros();
    active.marks[phase] = (now - active.startedMicros) / 1000.0;
  }

  void setDisplay({required int count, required double scale}) {
    final active = _active;
    if (active == null) {
      return;
    }
    active.displayCount = count < 0 ? 0 : count;
    active.displayScale = scale.isFinite && scale > 0 ? scale : null;
  }

  void finish(TimingOutcome outcome) {
    final active = _active;
    if (active == null) {
      return;
    }
    _active = null;
    final payload = <String, Object?>{
      'schema': 1,
      'outcome': outcome.name,
      if (active.displayCount != null) 'display_count': active.displayCount,
      if (active.displayScale != null) 'display_scale': active.displayScale,
      'total_ms': (_clock.nowMicros() - active.startedMicros) / 1000.0,
      'phases': {
        for (final entry in active.marks.entries)
          entry.key.jsonKey: entry.value,
      },
    };
    validateTimingPayload(payload);
    _sink?.appendLine(jsonEncode(payload));
  }
}

class _TimingActivation {
  _TimingActivation({required this.startedMicros});

  final int startedMicros;
  int? displayCount;
  double? displayScale;
  final marks = <TimingPhase, double>{};
}

const timingTopLevelKeys = {
  'schema',
  'outcome',
  'display_count',
  'display_scale',
  'total_ms',
  'phases',
};
const timingPhaseKeys = {
  'forward_ms',
  'portal_ms',
  'read_ms',
  'decode_ms',
  'map_ms',
  'crop_ms',
  'reveal_ms',
  'png_encode_ms',
  'ocr_dispatch_ms',
  'ocr_result_ms',
  'embed_ms',
  'prompt_ms',
  'mask_render_ms',
  'clipboard_ms',
  'first_paint_ms',
};
const timingOutcomeValues = {
  'ready',
  'dismissed',
  'failed',
  'permissionRequired',
  'copied',
  'saved',
  'cancelled',
};

void validateTimingPayload(Map<String, Object?> payload) {
  _rejectKeys(payload.keys, timingTopLevelKeys, 'timing');
  final outcome = payload['outcome'];
  if (outcome is! String || !timingOutcomeValues.contains(outcome)) {
    throw StateError('timing outcome is not allowlisted');
  }
  for (final entry in payload.entries) {
    final value = entry.value;
    if (entry.key == 'outcome' || entry.key == 'phases') {
      continue;
    }
    if (value is! num || !value.isFinite) {
      throw StateError('timing ${entry.key} must be numeric');
    }
  }
  final phases = payload['phases'];
  if (phases is! Map) {
    throw StateError('timing phases must be an object');
  }
  _rejectKeys(phases.keys, timingPhaseKeys, 'timing phases');
  for (final entry in phases.entries) {
    if (entry.value is! num || !(entry.value as num).isFinite) {
      throw StateError('timing phase ${entry.key} must be numeric');
    }
  }
}

void _rejectKeys(
  Iterable<Object?> actual,
  Set<String> allowed,
  String context,
) {
  final extra = actual.where((key) => key is! String || !allowed.contains(key));
  if (extra.isNotEmpty) {
    throw StateError('$context has non-allowlisted keys');
  }
}

final timingLogProvider = Provider<TimingLog>(
  (ref) => TimingLog.fromEnvironment(Platform.environment),
);
