import 'dart:async';

import 'package:kiriglyph/settings/app_settings.dart';
import 'package:kiriglyph/shortcut/shortcut_service.dart';

import 'support/settings_fakes.dart';

/// Runs before every test file. The app reads and writes the user's config
/// folder and GNOME keyboard settings, so tests get in-memory fakes unless a
/// test installs its own.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  settingsStoreFactory = MemorySettingsStore.new;
  shortcutServiceFactory = (_) => FakeShortcutService.configured();
  await testMain();
}
