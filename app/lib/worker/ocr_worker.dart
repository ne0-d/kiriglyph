import 'package:ubuntu_live_text/ocr/ocr_result.dart';

abstract class OcrWorker {
  Future<OcrResult> recognize(String imagePath);

  Future<void> close();
}
