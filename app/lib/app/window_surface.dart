import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dart entrypoint argument the runner adds for `--background` and
/// `--select` launches, whose window starts hidden.
const hiddenStartArgument = '--hidden-start';

/// Whether the process started with its window hidden.
final hiddenStartProvider = Provider<bool>((ref) => false);

/// Whether the window is presented as the normal app window.
///
/// While it is not, the app paints nothing visible: the hidden window keeps
/// its last frame and shows it again the next time it maps, so that frame
/// must be transparent rather than the dark main screen.
final mainWindowShownProvider = NotifierProvider<MainWindowShown, bool>(
  MainWindowShown.new,
);

class MainWindowShown extends Notifier<bool> {
  @override
  bool build() => !ref.read(hiddenStartProvider);

  void shown() => state = true;

  void hidden() => state = false;
}
