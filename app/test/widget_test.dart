import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/capture/instant_capture.dart';

import 'support/workspace_harness.dart';

void main() {
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('shows Kiriglyph setup window', (WidgetTester tester) async {
    await pumpApp(tester, worker: FakeWorker([sampleResult()]));

    expect(find.text('Kiriglyph'), findsOneWidget);
    expect(find.byKey(const Key('enable-instant-capture')), findsOneWidget);
    expect(find.byKey(const Key('quit-app')), findsOneWidget);
    expect(find.textContaining('Super+Shift+T'), findsOneWidget);
  });

  testWidgets('enable instant capture shows progress then granted', (
    WidgetTester tester,
  ) async {
    final permission = Completer<InstantCaptureStatus>();
    final instantCapture = FakeInstantCapture(permission.future);
    await pumpApp(
      tester,
      instantCapture: instantCapture,
      worker: FakeWorker([sampleResult()]),
    );

    await tester.tap(find.text('Enable instant capture'));
    await tester.pump();

    expect(instantCapture.calls, 1);
    expect(find.text('Requesting screen access…'), findsWidgets);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const Key('enable-instant-capture')),
          )
          .onPressed,
      isNull,
    );

    permission.complete(InstantCaptureStatus.granted);
    await tester.pump();

    expect(find.text('Instant capture is enabled.'), findsOneWidget);
  });

  testWidgets('enable instant capture explains denied permission', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      instantCapture: FakeInstantCapture(
        Future.value(InstantCaptureStatus.denied),
      ),
      worker: FakeWorker([sampleResult()]),
    );

    await tester.tap(find.byKey(const Key('enable-instant-capture')));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('GNOME asked for screen access and it was declined'),
      findsOneWidget,
    );
    expect(find.textContaining('Settings → Apps → Kiriglyph'), findsOneWidget);
  });

  testWidgets('copies the shortcut command', (WidgetTester tester) async {
    await pumpApp(
      tester,
      selectionCommand: 'kiriglyph --select --test',
      worker: FakeWorker([sampleResult()]),
    );

    await tester.tap(find.byKey(const Key('copy-selection-command')));
    await tester.pump();

    expect(clipboardText, 'kiriglyph --select --test');
    expect(find.text('Command copied'), findsOneWidget);
  });

  for (final size in const [Size(640, 300), Size(700, 500), Size(900, 600)]) {
    testWidgets('onboarding does not overflow at ${size.width.toInt()}x'
        '${size.height.toInt()}', (WidgetTester tester) async {
      await pumpApp(tester, size: size, worker: FakeWorker([sampleResult()]));

      expect(find.byKey(const Key('enable-instant-capture')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
