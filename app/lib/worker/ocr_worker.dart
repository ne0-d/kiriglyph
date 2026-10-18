import 'package:kiriglyph/ocr/ocr_result.dart';
import 'package:kiriglyph/protocol/worker_protocol.dart';

abstract class OcrWorker {
  Future<OcrResult> recognize(String imagePath);

  Future<List<DecodedCode>> decodeCodes(String imagePath);

  /// Cancels pending requests without stopping the warm worker process.
  Future<void> cancelInFlight();

  Future<void> cancelActive();

  Future<void> restart();

  Future<void> close();
}
