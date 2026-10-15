import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/capture/session_image_store.dart';

/// Requests the grant by taking one silent capture while the window is
/// focused; GNOME shows its access dialog for that first request.
class PortalInstantCapture implements InstantCapturePort {
  PortalInstantCapture(this._capture, this._store);

  final ScreenCapturePort _capture;
  final SessionImageStore _store;

  @override
  Future<InstantCaptureStatus> requestPermission() async {
    final ScreenCapture capture;
    try {
      capture = await _capture.capture();
    } catch (_) {
      return InstantCaptureStatus.failed;
    }
    switch (capture.status) {
      case ScreenCaptureStatus.captured:
        final path = capture.path;
        if (path != null) {
          await _store.deleteReturned(path);
        }
        return InstantCaptureStatus.granted;
      case ScreenCaptureStatus.ended || ScreenCaptureStatus.denied:
        return InstantCaptureStatus.denied;
      case ScreenCaptureStatus.unavailable:
        return InstantCaptureStatus.unavailable;
      default:
        return InstantCaptureStatus.failed;
    }
  }
}
