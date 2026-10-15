import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kiriglyph/protocol/protocol_error.dart';
import 'package:kiriglyph/segmentation/subject_segmenter.dart';
import 'package:kiriglyph/worker/process_ocr_worker.dart';

const _protocolVersion = 1;

class ProcessSubjectSegmenter implements SubjectSegmenter {
  ProcessSubjectSegmenter(
    this._launchConfig, {
    this.requestTimeout = const Duration(seconds: 45),
    this.shutdownTimeout = const Duration(seconds: 2),
    this.forceKillTimeout = const Duration(milliseconds: 500),
    this.onDiagnostic,
  });

  final WorkerLaunchConfig _launchConfig;
  final Duration requestTimeout;
  final Duration shutdownTimeout;
  final Duration forceKillTimeout;
  final void Function(String message)? onDiagnostic;
  final _pending = <String, Completer<Object>>{};
  final _maskPaths = <String>{};
  int _counter = 0;
  bool _closed = false;
  Process? _process;
  Future<void>? _starting;
  Future<void> _writeTail = Future<void>.value();
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;

  @override
  Future<SubjectEmbedding> embed(String imagePath) async {
    final result = await _send('embed', {
      'source': 'path',
      'image_path': imagePath,
    }, timeoutMessage: 'subject embedding timed out');
    return _parseEmbedding(result);
  }

  @override
  Future<SubjectMaskResult> prompt(
    SubjectEmbedding embedding,
    SubjectPrompt prompt,
  ) async {
    final result = await _send('prompt', {
      'handle': _embeddingToJson(embedding),
      'prompt': prompt.toJson(),
    }, timeoutMessage: 'subject prompt timed out');
    final parsed = _parseMaskResult(result);
    _maskPaths.add(parsed.mask.path);
    return parsed;
  }

  @override
  Future<void> cancelActive() async {
    final targets = _pending.keys.toList(growable: false);
    for (final target in targets) {
      final completer = _pending.remove(target);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          const SubjectSegmentationException(
            kind: SubjectFailureKind.cancelled,
            message: 'subject segmentation was cancelled',
          ),
        );
      }
      try {
        await _writeProtocolRequest('cancel', {
          'request_id': target,
        }, waitForResponse: false);
      } on Object {
        // If the process has already gone away, local cancellation is enough.
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _failAll(
      const SubjectSegmentationException(
        kind: SubjectFailureKind.sessionClosed,
        message: 'subject segmenter closed',
      ),
    );
    try {
      await _starting;
    } catch (_) {
      // Failed startup has no child process to close.
    }
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await _writeRaw(
          process,
          utf8.encode(_requestLine('close', {}, 'close')),
        );
      } on Object {
        // The child may already be exiting.
      }
      try {
        await process.stdin.close();
      } on Object {
        // The worker may already have closed stdin.
      }
      if (!await _waitForExit(process, shutdownTimeout)) {
        process.kill();
        if (!await _waitForExit(process, forceKillTimeout)) {
          process.kill(ProcessSignal.sigkill);
          await _waitForExit(process, forceKillTimeout);
        }
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    for (final path in _maskPaths.toList(growable: false)) {
      await deleteMaskFile(path);
    }
    _maskPaths.clear();
  }

  Future<Object> _send(
    String method,
    Map<String, Object?> params, {
    required String timeoutMessage,
  }) async {
    final id = await _writeProtocolRequest(method, params);
    final completer = _pending[id]!;
    try {
      return await completer.future.timeout(
        requestTimeout,
        onTimeout: () {
          _pending.remove(id);
          final error = SubjectSegmentationException(
            kind: SubjectFailureKind.timeout,
            message: timeoutMessage,
          );
          _terminateForFailure(error);
          throw error;
        },
      );
    } on WorkerError catch (error) {
      throw _mapWorkerError(error);
    }
  }

  Future<String> _writeProtocolRequest(
    String method,
    Map<String, Object?> params, {
    bool waitForResponse = true,
  }) async {
    await _ensureStarted();
    final id = 'seg-${++_counter}-${DateTime.now().microsecondsSinceEpoch}';
    if (waitForResponse) {
      _pending[id] = Completer<Object>();
    }
    await _writeRaw(_process!, utf8.encode(_requestLine(method, params, id)));
    return id;
  }

  String _requestLine(String method, Map<String, Object?> params, String id) =>
      '${jsonEncode({'version': _protocolVersion, 'id': id, 'method': method, 'params': params})}\n';

  Future<void> _ensureStarted() async {
    if (_closed) {
      throw const SubjectSegmentationException(
        kind: SubjectFailureKind.sessionClosed,
        message: 'subject segmenter is closed',
      );
    }
    if (_process != null) {
      return;
    }
    final existing = _starting;
    if (existing != null) {
      return existing;
    }
    final start = _startProcess();
    _starting = start;
    try {
      await start;
    } finally {
      if (identical(_starting, start)) {
        _starting = null;
      }
    }
  }

  Future<void> _startProcess() async {
    final process =
        await Process.start(
          _launchConfig.executable,
          _launchConfig.arguments,
          workingDirectory: _launchConfig.workingDirectory,
          environment: _launchConfig.environment,
        ).onError<ProcessException>((_, _) {
          throw const SubjectSegmentationException(
            kind: SubjectFailureKind.processDied,
            message: 'segmentation worker process could not be started',
          );
        });
    if (_closed) {
      process.kill();
      throw const SubjectSegmentationException(
        kind: SubjectFailureKind.sessionClosed,
        message: 'subject segmenter is closed',
      );
    }
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(
          (line) => _dispatchLine(line),
          onError: (Object _) => _terminateForFailure(
            const SubjectSegmentationException(
              kind: SubjectFailureKind.processDied,
              message: 'segmentation stdout failed',
            ),
          ),
          onDone: () {
            if (!identical(_process, process)) {
              return;
            }
            _process = null;
            _failAll(
              const SubjectSegmentationException(
                kind: SubjectFailureKind.processDied,
                message: 'segmentation worker exited unexpectedly',
              ),
            );
          },
        );
    _stderrSubscription = process.stderr.listen(
      (_) => onDiagnostic?.call('segmentation diagnostic received'),
    );
  }

  Future<void> _writeRaw(Process process, List<int> bytes) {
    final write = _writeTail.then((_) async {
      if (!identical(_process, process)) {
        throw ProtocolError('segmentation process changed before request');
      }
      process.stdin.add(bytes);
      await process.stdin.flush();
    });
    _writeTail = write.then<void>((_) {}, onError: (_, _) {});
    return write;
  }

  void _dispatchLine(String line) {
    String? responseId;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded['id'] is String) {
        responseId = decoded['id'] as String;
      }
    } catch (_) {
      _terminateForFailure(
        const SubjectSegmentationException(
          kind: SubjectFailureKind.malformedOutput,
          message: 'segmentation worker sent malformed JSON',
        ),
      );
      return;
    }
    if (responseId == null) {
      _terminateForFailure(
        const SubjectSegmentationException(
          kind: SubjectFailureKind.malformedOutput,
          message: 'segmentation worker response missed an ID',
        ),
      );
      return;
    }
    final completer = _pending.remove(responseId);
    if (completer == null) {
      return;
    }
    try {
      completer.complete(_parseResponse(line, responseId));
    } on Object catch (error) {
      completer.completeError(error);
      _terminateForFailure(
        const SubjectSegmentationException(
          kind: SubjectFailureKind.malformedOutput,
          message: 'segmentation worker sent a malformed response',
        ),
      );
    }
  }

  Object _parseResponse(String line, String expectedId) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw ProtocolError('response must be an object');
    }
    if (decoded['version'] != _protocolVersion || decoded['id'] != expectedId) {
      throw ProtocolError('response envelope mismatch');
    }
    final ok = decoded['ok'];
    if (ok is! bool) {
      throw ProtocolError('response ok must be a boolean');
    }
    if (ok) {
      final result = decoded['result'];
      if (result is! Map) {
        throw ProtocolError('result must be an object');
      }
      return result;
    }
    final error = decoded['error'];
    if (error is! Map) {
      throw ProtocolError('error must be an object');
    }
    final code = error['code'];
    final message = error['message'];
    if (code is! String || message is! String) {
      throw ProtocolError('error code and message must be strings');
    }
    final details = error['details'];
    throw WorkerError(
      code: code,
      message: message,
    ).withDetails(details is Map ? details : null);
  }

  void _terminateForFailure(Object error) {
    final process = _process;
    _process = null;
    _failAll(error);
    process?.kill();
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.future.ignore();
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  Future<bool> _waitForExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

extension on WorkerError {
  WorkerError withDetails(Map? details) =>
      _DetailedWorkerError(code: code, message: message, details: details);
}

class _DetailedWorkerError extends WorkerError {
  _DetailedWorkerError({
    required super.code,
    required super.message,
    required this.details,
  });

  final Map? details;
}

SubjectSegmentationException _mapWorkerError(WorkerError error) {
  final details = error is _DetailedWorkerError ? error.details : null;
  return SubjectSegmentationException(
    kind: _failureKind(error.code),
    message: error.message,
    command: details?['command'] is String
        ? details!['command'] as String
        : null,
  );
}

SubjectFailureKind _failureKind(String code) => switch (code) {
  'cancelled' => SubjectFailureKind.cancelled,
  'timeout' => SubjectFailureKind.timeout,
  'malformed_output' => SubjectFailureKind.malformedOutput,
  'model_load_failed' => SubjectFailureKind.modelLoadFailed,
  'model_missing' => SubjectFailureKind.modelMissing,
  'process_died' => SubjectFailureKind.processDied,
  'out_of_memory' => SubjectFailureKind.outOfMemory,
  'session_closed' => SubjectFailureKind.sessionClosed,
  _ => SubjectFailureKind.malformedOutput,
};

Map<String, Object?> _embeddingToJson(SubjectEmbedding embedding) => {
  'handle': embedding.handle,
  'image': {'width': embedding.imageWidth, 'height': embedding.imageHeight},
  'timings_ms': _timingsToJson(embedding.timings),
};

Map<String, Object?> _timingsToJson(SubjectSegmentationTimings timings) => {
  if (timings.loadMs != null) 'load_ms': timings.loadMs,
  if (timings.embedMs != null) 'embed_ms': timings.embedMs,
  if (timings.firstMaskMs != null) 'first_mask_ms': timings.firstMaskMs,
  if (timings.promptMs != null) 'prompt_ms': timings.promptMs,
};

SubjectEmbedding _parseEmbedding(Object raw) {
  final map = _map(raw, 'result');
  final image = _map(map['image'], 'result.image');
  return SubjectEmbedding(
    handle: _string(map['handle'], 'result.handle'),
    imageWidth: _positiveInt(image['width'], 'result.image.width'),
    imageHeight: _positiveInt(image['height'], 'result.image.height'),
    timings: _parseTimings(map['timings_ms']),
  );
}

SubjectMaskResult _parseMaskResult(Object raw) {
  final map = _map(raw, 'result');
  final image = _map(map['image'], 'result.image');
  final mask = _map(map['mask'], 'result.mask');
  final stats = _parseStats(map['mask_stats']);
  return SubjectMaskResult(
    imageWidth: _positiveInt(image['width'], 'result.image.width'),
    imageHeight: _positiveInt(image['height'], 'result.image.height'),
    mask: SubjectMaskReference(
      path: _string(mask['path'], 'result.mask.path'),
      byteLength: _positiveInt(mask['byte_length'], 'result.mask.byte_length'),
      sha256: _string(mask['sha256'], 'result.mask.sha256'),
    ),
    bounds: _optionalRect(map['bounds'], 'result.bounds'),
    stats: stats,
    confidence: _optionalUnit(map['confidence'], 'result.confidence'),
    stabilityScore: _optionalUnit(
      map['stability_score'],
      'result.stability_score',
    ),
    timings: _parseTimings(map['timings_ms']),
  );
}

SubjectMaskStats _parseStats(Object? raw) {
  final map = _map(raw, 'result.mask_stats');
  return SubjectMaskStats(
    outcome: switch (_string(map['outcome'], 'result.mask_stats.outcome')) {
      'ok' => SubjectMaskOutcome.ok,
      'empty' => SubjectMaskOutcome.empty,
      'suspect_full_image' => SubjectMaskOutcome.suspectFullImage,
      _ => throw ProtocolError('unsupported mask outcome'),
    },
    areaFraction: _unit(
      map['area_fraction'],
      'result.mask_stats.area_fraction',
    ),
    bounds: _optionalRect(map['bounds'], 'result.mask_stats.bounds'),
    touchesEdge: _parseTouches(map['touches_edge']),
    components: _parseComponents(map['components']),
  );
}

SubjectEdgeTouches _parseTouches(Object? raw) {
  final map = _map(raw, 'result.mask_stats.touches_edge');
  return SubjectEdgeTouches(
    left: _bool(map['left'], 'touches_edge.left'),
    top: _bool(map['top'], 'touches_edge.top'),
    right: _bool(map['right'], 'touches_edge.right'),
    bottom: _bool(map['bottom'], 'touches_edge.bottom'),
  );
}

SubjectComponentStats _parseComponents(Object? raw) {
  final map = _map(raw, 'result.mask_stats.components');
  return SubjectComponentStats(
    count: _nonnegativeInt(map['count'], 'components.count'),
    largestBounds: _optionalRect(
      map['largest_bounds'],
      'components.largest_bounds',
    ),
  );
}

SubjectSegmentationTimings _parseTimings(Object? raw) {
  final map = raw == null
      ? const <Object?, Object?>{}
      : _map(raw, 'timings_ms');
  return SubjectSegmentationTimings(
    loadMs: _optionalNumber(map['load_ms'], 'load_ms'),
    embedMs: _optionalNumber(map['embed_ms'], 'embed_ms'),
    firstMaskMs: _optionalNumber(map['first_mask_ms'], 'first_mask_ms'),
    promptMs: _optionalNumber(map['prompt_ms'], 'prompt_ms'),
  );
}

SubjectRect? _optionalRect(Object? raw, String field) =>
    raw == null ? null : _parseRect(raw, field);

SubjectRect _parseRect(Object raw, String field) {
  final map = _map(raw, field);
  return SubjectRect(
    x: _int(map['x'], '$field.x'),
    y: _int(map['y'], '$field.y'),
    width: _positiveInt(map['width'], '$field.width'),
    height: _positiveInt(map['height'], '$field.height'),
  );
}

Map _map(Object? raw, String field) {
  if (raw is! Map) {
    throw ProtocolError('$field must be an object');
  }
  return raw;
}

String _string(Object? raw, String field) {
  if (raw is! String || raw.isEmpty) {
    throw ProtocolError('$field must be a non-empty string');
  }
  return raw;
}

bool _bool(Object? raw, String field) {
  if (raw is! bool) {
    throw ProtocolError('$field must be a boolean');
  }
  return raw;
}

int _int(Object? raw, String field) {
  if (raw is! int) {
    throw ProtocolError('$field must be an integer');
  }
  return raw;
}

int _positiveInt(Object? raw, String field) {
  final value = _int(raw, field);
  if (value < 1) {
    throw ProtocolError('$field must be positive');
  }
  return value;
}

int _nonnegativeInt(Object? raw, String field) {
  final value = _int(raw, field);
  if (value < 0) {
    throw ProtocolError('$field must be non-negative');
  }
  return value;
}

double _unit(Object? raw, String field) {
  final value = _number(raw, field);
  if (value < 0 || value > 1) {
    throw ProtocolError('$field must be between 0 and 1');
  }
  return value;
}

double? _optionalUnit(Object? raw, String field) =>
    raw == null ? null : _unit(raw, field);

double? _optionalNumber(Object? raw, String field) =>
    raw == null ? null : _number(raw, field);

double _number(Object? raw, String field) {
  if (raw is! num || !raw.isFinite) {
    throw ProtocolError('$field must be a finite number');
  }
  return raw.toDouble();
}
