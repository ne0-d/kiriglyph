import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_lifecycle.dart';
import 'package:kiriglyph/ui/kiriglyph_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  AppLifecycle(container).start();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KiriglyphApp(),
    ),
  );
}
