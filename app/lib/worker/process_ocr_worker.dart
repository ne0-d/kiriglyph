import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';
import 'package:ubuntu_live_text/protocol/worker_protocol.dart';
import 'package:ubuntu_live_text/worker/ocr_worker.dart';

class WorkerLaunchConfig {
  const WorkerLaunchConfig({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}

class ProcessOcrWorker implements OcrWorker {
  ProcessOcrWorker(
    this._launchConfig, {
    this.requestTimeout = const Duration(seconds: 30),
    this.shutdownTimeout = const Duration(seconds: 2),
    this.forceKillTimeout = const Duration(milliseconds: 500),
    this.onDiagnostic,
  });

  final WorkerLaunchConfig _launchConfig;
  final Duration requestTimeout;
  final Duration shutdownTimeout;
  final Duration forceKillTimeout;
  final void Function(String message)? onDiagnostic;
  int _requestCounter = 0;
  int _generation = 0;
  bool _closed = false;

  Process? _process;
  Future<void>? _starting;
  Future<void> _writeTail = Future<void>.value();
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  final _pending =
      <String, Completer<({OcrResult? result, WorkerError? error})>>{};

  Future<void> _ensureStarted() async {
    if (_closed) {
      throw const WorkerProcessError(
        kind: WorkerFailureKind.closed,
        message: 'worker is closed',
      );
    }
    if (_process != null) {
      return;
    }

    final existingStart = _starting;
    if (existingStart != null) {
      return existingStart;
    }

    final start = _startProcess(_generation);
    _starting = start;
    try {
      await start;
    } finally {
      if (identical(_starting, start)) {
        _starting = null;
      }
    }
  }

  Future<void> _startProcess(int generation) async {
    final Process process;
    try {
      process = await Process.start(
        _launchConfig.executable,
        _launchConfig.arguments,
        workingDirectory: _launchConfig.workingDirectory,
        environment: _launchConfig.environment,
      );
    } on ProcessException {
      throw const WorkerProcessError(
        kind: WorkerFailureKind.startup,
        message: 'worker process could not be started',
      );
    }
    if (_closed || generation != _generation) {
      process.kill();
      throw WorkerProcessError(
        kind: _closed ? WorkerFailureKind.closed : WorkerFailureKind.cancelled,
        message: _closed
            ? 'worker is closed'
            : 'worker recognition was cancelled',
      );
    }
    _process = process;

    _stdoutSubscription = process.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(
          (line) => _dispatchLine(process, line),
          onError: (Object _) {
            _terminateForFailure(
              process,
              const WorkerProcessError(
                kind: WorkerFailureKind.exited,
                message: 'worker stdout stream failed',
              ),
            );
          },
          onDone: () {
            if (!identical(_process, process)) {
              return;
            }
            _process = null;
            _stdoutSubscription = null;
            _failAll(
              const WorkerProcessError(
                kind: WorkerFailureKind.exited,
                message: 'worker process exited unexpectedly',
              ),
            );
          },
        );

    _stderrSubscription = process.stderr.listen(
      (_) => onDiagnostic?.call('worker diagnostic received'),
    );
  }

  Future<void> _writeRequest(Process process, List<int> bytes) {
    final write = _writeTail.then((_) async {
      if (!identical(_process, process)) {
        throw ProtocolError('worker process changed before request was sent');
      }
      process.stdin.add(bytes);
      await process.stdin.flush();
    });
    _writeTail = write.then<void>((_) {}, onError: (_, _) {});
    return write;
  }

  void _dispatchLine(Process process, String line) {
    String? responseId;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded['id'] is String) {
        responseId = decoded['id'] as String;
      }
    } catch (_) {
      _terminateForFailure(
        process,
        const WorkerProcessError(
          kind: WorkerFailureKind.malformedResponse,
          message: 'worker sent malformed JSON',
        ),
      );
      return;
    }

    if (responseId == null) {
      _terminateForFailure(
        process,
        const WorkerProcessError(
          kind: WorkerFailureKind.malformedResponse,
          message: 'worker response did not include a request ID',
        ),
      );
      return;
    }

    if (!_pending.containsKey(responseId)) {
      return;
    }

    final completer = _pending.remove(responseId)!;
    try {
      final parsed = parseResponseLine(line, expectedId: responseId);
      completer.complete(parsed);
    } on ProtocolError catch (error) {
      completer.completeError(
        WorkerProcessError(
          kind: WorkerFailureKind.malformedResponse,
          message: error.message,
        ),
      );
      _terminateForFailure(
        process,
        const WorkerProcessError(
          kind: WorkerFailureKind.malformedResponse,
          message: 'worker sent a malformed response',
        ),
      );
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  void _terminateForFailure(Process process, Object error) {
    if (!identical(_process, process)) {
      return;
    }
    _process = null;
    _stdoutSubscription = null;
    unawaited(_stderrSubscription?.cancel());
    _stderrSubscription = null;
    _failAll(error);
    process.kill();
  }

  @override
  Future<OcrResult> recognize(String imagePath) async {
    await _ensureStarted();
    final id =
        'req-${++_requestCounter}-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<({OcrResult? result, WorkerError? error})>();
    _pending[id] = completer;

    final requestLine =
        '${encodeRecognizeRequest(id: id, imagePath: imagePath)}\n';
    final process = _process!;
    await _writeRequest(process, utf8.encode(requestLine));
    final response = await completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        final error = WorkerProcessError(
          kind: WorkerFailureKind.timeout,
          message: 'worker recognition timed out',
        );
        _terminateForFailure(process, error);
        throw error;
      },
    );
    final workerError = response.error;
    if (workerError != null) {
      throw workerError;
    }
    final result = response.result;
    if (result == null) {
      throw ProtocolError('successful response missing result');
    }
    return result;
  }

  @override
  Future<void> cancelActive() async {
    _generation++;
    _failAll(
      const WorkerProcessError(
        kind: WorkerFailureKind.cancelled,
        message: 'worker recognition was cancelled',
      ),
    );
    try {
      await _starting;
    } catch (_) {
      // A cancelled or failed startup has no active process to terminate.
    }
    final process = _process;
    _process = null;
    final stdoutSubscription = _stdoutSubscription;
    final stderrSubscription = _stderrSubscription;
    _stdoutSubscription = null;
    _stderrSubscription = null;
    if (process != null) {
      process.kill();
      if (!await _waitForExit(process, forceKillTimeout)) {
        process.kill(ProcessSignal.sigkill);
        await _waitForExit(process, forceKillTimeout);
      }
    }
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
  }

  @override
  Future<void> restart() async {
    if (_closed) {
      throw const WorkerProcessError(
        kind: WorkerFailureKind.closed,
        message: 'worker is closed',
      );
    }
    await cancelActive();
    await _ensureStarted();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation++;
    try {
      await _starting;
    } catch (_) {
      // A failed startup has no child process to close.
    }

    _failAll(
      const WorkerProcessError(
        kind: WorkerFailureKind.closed,
        message: 'worker closed',
      ),
    );
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.stdin.close();
      } on Object {
        // The worker may already have closed its stdin.
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
