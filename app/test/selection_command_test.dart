import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/app/app_identity.dart';
import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/capture/portal_instant_capture.dart';
import 'package:kiriglyph/capture/screen_capture.dart';
import 'package:kiriglyph/capture/session_image_store.dart';
import 'package:kiriglyph/providers.dart';

import 'support/overlay_fakes.dart';

void main() {
  late Directory root;
  late Directory pictures;
  late FakeSilentPortal portal;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('selection-command-');
    pictures = Directory('${root.path}/Pictures')..createSync();
    final runtime = Directory('${root.path}/runtime')..createSync();
    portal = FakeSilentPortal(pictures);
    container = ProviderContainer(
      overrides: [
        sessionImageStoreProvider.overrideWithValue(
          SessionImageStore(root: runtime),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  group('instant capture permission', () {
    Future<InstantCaptureStatus> request(ScreenCaptureStatus status) {
      portal.status = status;
      return PortalInstantCapture(
        portal,
        container.read(sessionImageStoreProvider),
      ).requestPermission();
    }

    test('a granted capture deletes its file', () async {
      expect(
        await request(ScreenCaptureStatus.captured),
        InstantCaptureStatus.granted,
      );
      expect(pictures.listSync(), isEmpty);
    });

    test('portal outcomes map to permission statuses', () async {
      for (final (status, expected) in const [
        (ScreenCaptureStatus.ended, InstantCaptureStatus.denied),
        (ScreenCaptureStatus.denied, InstantCaptureStatus.denied),
        (ScreenCaptureStatus.unavailable, InstantCaptureStatus.unavailable),
        (ScreenCaptureStatus.failed, InstantCaptureStatus.failed),
        (ScreenCaptureStatus.unreadable, InstantCaptureStatus.failed),
      ]) {
        expect(await request(status), expected, reason: '$status');
      }
    });
  });

  test('the selection command uses the installed launcher', () {
    expect(
      selectionCommand(environment: {'HOME': '/home/neo'}),
      '/home/neo/.local/bin/kiriglyph --select',
    );
    expect(
      selectionCommand(environment: {'HOME': "/home/o'neil x"}),
      r"'/home/o'\''neil x/.local/bin/kiriglyph' --select",
    );
  });
}
