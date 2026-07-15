import 'dart:convert';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/protocol/protocol_error.dart';

const protocolVersion = 1;

String encodeRecognizeRequest({required String id, required String imagePath}) {
  return jsonEncode({
    'version': protocolVersion,
    'id': id,
    'method': 'recognize',
    'params': {'image_path': imagePath},
  });
}

OcrResult parseSuccessResult(Object? raw) {
  if (raw is! Map) {
    throw ProtocolError('result must be a JSON object');
  }

  final image = raw['image'];
  if (image is! Map) {
    throw ProtocolError('result.image must be an object');
  }
  final width = _requireInt(image['width'], field: 'result.image.width');
  final height = _requireInt(image['height'], field: 'result.image.height');
  if (width < 1 || height < 1) {
    throw ProtocolError('result.image dimensions must be positive');
  }

  final fullText = raw['full_text'];
  if (fullText is! String) {
    throw ProtocolError('result.full_text must be a string');
  }

  final regionsRaw = raw['regions'];
  if (regionsRaw is! List) {
    throw ProtocolError('result.regions must be an array');
  }

  final regions = <TextRegion>[];
  for (var i = 0; i < regionsRaw.length; i++) {
    regions.add(_parseRegion(regionsRaw[i], index: i));
  }

  final timingsRaw = raw['timings_ms'];
  if (timingsRaw is! Map) {
    throw ProtocolError('result.timings_ms must be an object');
  }
  final total = timingsRaw['total'];
  if (total is! num || total < 0) {
    throw ProtocolError(
      'result.timings_ms.total must be a non-negative number',
    );
  }

  _rejectExtraKeys(raw, {
    'image',
    'full_text',
    'regions',
    'timings_ms',
  }, 'result');

  return OcrResult(
    imageWidth: width,
    imageHeight: height,
    fullText: fullText,
    regions: regions,
    timingsMs: TimingsMs(total: total),
  );
}

TextRegion _parseRegion(Object? raw, {required int index}) {
  if (raw is! Map) {
    throw ProtocolError('result.regions[$index] must be an object');
  }

  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw ProtocolError('result.regions[$index].id must be a non-empty string');
  }

  final levelRaw = raw['level'];
  if (levelRaw != 'line') {
    throw ProtocolError('result.regions[$index].level must be "line"');
  }

  final text = raw['text'];
  if (text is! String) {
    throw ProtocolError('result.regions[$index].text must be a string');
  }

  final polygonRaw = raw['polygon'];
  if (polygonRaw is! List || polygonRaw.length != 4) {
    throw ProtocolError('result.regions[$index].polygon must have four points');
  }
  final polygon = <Point>[];
  for (var p = 0; p < 4; p++) {
    final point = polygonRaw[p];
    if (point is! List || point.length != 2) {
      throw ProtocolError('result.regions[$index].polygon[$p] must be [x, y]');
    }
    final x = point[0];
    final y = point[1];
    if (x is! num || y is! num) {
      throw ProtocolError(
        'result.regions[$index].polygon[$p] coordinates must be numbers',
      );
    }
    polygon.add(Point(x: x.toDouble(), y: y.toDouble()));
  }

  final confidence = raw['confidence'];
  if (confidence is! num || confidence < 0 || confidence > 1) {
    throw ProtocolError(
      'result.regions[$index].confidence must be between 0 and 1',
    );
  }

  final readingOrder = raw['reading_order'];
  if (readingOrder is! int || readingOrder < 0) {
    throw ProtocolError(
      'result.regions[$index].reading_order must be a non-negative integer',
    );
  }

  _rejectExtraKeys(raw, {
    'id',
    'level',
    'text',
    'polygon',
    'confidence',
    'reading_order',
  }, 'result.regions[$index]');

  return TextRegion(
    id: id,
    level: TextRegionLevel.line,
    text: text,
    polygon: polygon,
    confidence: confidence.toDouble(),
    readingOrder: readingOrder,
  );
}

({OcrResult? result, WorkerError? error}) parseResponseLine(
  String line, {
  required String expectedId,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    throw ProtocolError('response line is not valid JSON');
  }

  if (decoded is! Map) {
    throw ProtocolError('response must be a JSON object');
  }

  if (decoded['version'] != protocolVersion) {
    throw ProtocolError('unsupported protocol version');
  }

  final id = decoded['id'];
  if (id is! String || id.isEmpty) {
    throw ProtocolError('response id must be a non-empty string');
  }
  if (id != expectedId) {
    throw ProtocolError('response id does not match request');
  }

  final ok = decoded['ok'];
  if (ok is! bool) {
    throw ProtocolError('response ok must be a boolean');
  }

  _rejectExtraKeys(decoded, {
    'version',
    'id',
    'ok',
    'result',
    'error',
  }, 'response');

  if (ok) {
    if (decoded.containsKey('error')) {
      throw ProtocolError('successful response must not include error');
    }
    return (result: parseSuccessResult(decoded['result']), error: null);
  }

  if (decoded.containsKey('result')) {
    throw ProtocolError('error response must not include result');
  }

  final errorRaw = decoded['error'];
  if (errorRaw is! Map) {
    throw ProtocolError('error response must include error object');
  }
  final code = errorRaw['code'];
  final message = errorRaw['message'];
  if (code is! String || code.isEmpty) {
    throw ProtocolError('error.code must be a non-empty string');
  }
  if (message is! String || message.isEmpty) {
    throw ProtocolError('error.message must be a non-empty string');
  }
  _rejectExtraKeys(errorRaw, {'code', 'message'}, 'error');

  return (result: null, error: WorkerError(code: code, message: message));
}

int _requireInt(Object? value, {required String field}) {
  if (value is! int) {
    throw ProtocolError('$field must be an integer');
  }
  return value;
}

void _rejectExtraKeys(Map raw, Set<String> allowed, String context) {
  final extra = raw.keys.where((k) => !allowed.contains(k)).toList();
  if (extra.isNotEmpty) {
    throw ProtocolError('$context has unexpected fields: ${extra.join(', ')}');
  }
}
