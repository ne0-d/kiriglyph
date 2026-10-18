import 'package:flutter_riverpod/flutter_riverpod.dart';

final shortcutPauseProvider = NotifierProvider<ShortcutPauseController, bool>(
  ShortcutPauseController.new,
);

class ShortcutPauseController extends Notifier<bool> {
  @override
  bool build() => false;

  void setPaused(bool paused) => state = paused;

  void toggle() => state = !state;
}
