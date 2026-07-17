class ProtocolError implements Exception {
  ProtocolError(this.message);

  final String message;

  @override
  String toString() => 'ProtocolError: $message';
}

class WorkerError implements Exception {
  WorkerError({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'WorkerError($code): $message';
}

enum WorkerFailureKind {
  startup,
  exited,
  timeout,
  malformedResponse,
  cancelled,
  closed,
}

class WorkerProcessError implements Exception {
  const WorkerProcessError({required this.kind, required this.message});

  final WorkerFailureKind kind;
  final String message;

  @override
  String toString() => 'WorkerProcessError(${kind.name}): $message';
}
