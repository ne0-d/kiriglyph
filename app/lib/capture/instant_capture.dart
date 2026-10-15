import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_identity.dart' as identity;
import 'package:kiriglyph/capture/portal_helper_capture.dart';
import 'package:kiriglyph/capture/portal_instant_capture.dart';
import 'package:kiriglyph/providers.dart';

enum InstantCaptureStatus { granted, denied, unavailable, failed }

/// One-time GNOME permission for silent captures. GNOME shows its access
/// dialog only while this app's window is focused, so call this from a user
/// action in the visible window.
abstract interface class InstantCapturePort {
  Future<InstantCaptureStatus> requestPermission();
}

final instantCaptureProvider = Provider<InstantCapturePort>((ref) {
  // A separate helper runner, so a permission request never cancels an
  // in-flight selection capture.
  final capture = PortalHelperScreenCapture(silentCaptureLaunchConfig());
  ref.onDispose(capture.cancel);
  return PortalInstantCapture(capture, ref.watch(sessionImageStoreProvider));
});

/// Command the user binds to a GNOME custom shortcut to enter selection mode.
final selectionCommandProvider = Provider<String>(
  (ref) => identity.selectionCommand(),
);
