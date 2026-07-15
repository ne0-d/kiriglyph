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
