import 'package:kiriglyph/ocr/ocr_result.dart';

abstract class OcrWorker {
  Future<OcrResult> recognize(String imagePath);

  Future<void> cancelActive();

  Future<void> restart();

  Future<void> close();
}
