import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/settings/app_settings.dart';
import 'package:kiriglyph/shortcut/accelerator.dart';
import 'package:kiriglyph/shortcut/shortcut_service.dart';

/// What the preferences window shows about the shortcut.
class ShortcutState {
  const ShortcutState({
    this.binding,
    this.addedAutomatically = false,
    this.error,
  });

  final ShortcutBinding? binding;

  /// The app picked it on first run, so the window says so.
  final bool addedAutomatically;

  /// Why the shortcut cannot be managed here, if it cannot.
  final String? error;
}

/// Shortcuts tried, in order, when the app adds one on first run. The first
/// with no conflict wins.
final defaultShortcutCandidates = <Accelerator>[
  Accelerator({AcceleratorModifier.control, AcceleratorModifier.superKey}, 't'),
  Accelerator({AcceleratorModifier.superKey, AcceleratorModifier.shift}, 't'),
  Accelerator({
    AcceleratorModifier.control,
    AcceleratorModifier.alt,
    AcceleratorModifier.superKey,
  }, 't'),
  Accelerator({AcceleratorModifier.control, AcceleratorModifier.alt}, 'k'),
];

final shortcutControllerProvider =
    AsyncNotifierProvider<ShortcutController, ShortcutState>(
      ShortcutController.new,
    );

class ShortcutController extends AsyncNotifier<ShortcutState> {
  /// Reads the shortcut. On the very first run, when there is none, adds the
  /// first free candidate; it never adds one again after that.
  @override
  Future<ShortcutState> build() async {
    final service = ref.watch(shortcutServiceProvider);
    try {
      var binding = await service.current();
      var added = false;
      final settings = await ref.read(appSettingsProvider.future);
      if (!settings.shortcutAutoSetupDone) {
        if (binding == null) {
          for (final candidate in defaultShortcutCandidates) {
            if (await service.findConflict(candidate) == null) {
              binding = await service.set(candidate);
              added = true;
              break;
            }
          }
        }
        await ref
            .read(appSettingsProvider.notifier)
            .markShortcutAutoSetupDone();
      }
      return ShortcutState(binding: binding, addedAutomatically: added);
    } on ShortcutException catch (error) {
      return ShortcutState(error: error.message);
    }
  }

  /// Sets [accelerator] unless something else uses it. Returns what is in the
  /// way, or null on success; throws [ShortcutException] if writing fails.
  Future<ShortcutConflict?> change(Accelerator accelerator) async {
    final service = ref.read(shortcutServiceProvider);
    final conflict = await service.findConflict(accelerator);
    if (conflict != null) {
      return conflict;
    }
    final binding = await service.set(accelerator);
    state = AsyncData(ShortcutState(binding: binding));
    return null;
  }
}
