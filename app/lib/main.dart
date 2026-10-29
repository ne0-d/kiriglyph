import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_lifecycle.dart';
import 'package:kiriglyph/app/window_surface.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      hiddenStartProvider.overrideWithValue(args.contains(hiddenStartArgument)),
    ],
  );
  AppLifecycle(container).start();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KiriglyphApp(),
    ),
  );
}
