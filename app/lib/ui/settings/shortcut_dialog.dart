import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/shortcut/accelerator.dart';
import 'package:kiriglyph/shortcut/shortcut_controller.dart';
import 'package:kiriglyph/shortcut/shortcut_service.dart';
import 'package:kiriglyph/theme/app_theme.dart';

/// Records a new shortcut from the keyboard, warns about anything already
/// using it, and saves it to GNOME's keyboard settings.
class ShortcutDialog extends ConsumerStatefulWidget {
  const ShortcutDialog({super.key});

  @override
  ConsumerState<ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends ConsumerState<ShortcutDialog> {
  Accelerator? _captured;
  String? _problem;
  bool _checking = false;
  bool _saving = false;

  /// What the last key press asked for, so a slow conflict check for an older
  /// press cannot overwrite a newer one.
  int _serial = 0;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _saving) {
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed;
    final alt = keyboard.isAltPressed;
    final shift = keyboard.isShiftPressed;
    final superKey = keyboard.isMetaPressed;
    final bare = !control && !alt && !shift && !superKey;
    if (bare && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (bare && event.logicalKey == LogicalKeyboardKey.enter) {
      if (_canSave) {
        _save();
      }
      return KeyEventResult.handled;
    }
    final accelerator = acceleratorFromKey(
      event.logicalKey,
      control: control,
      alt: alt,
      shift: shift,
      superKey: superKey,
    );
    if (accelerator != null) {
      _consider(accelerator);
    }
    return KeyEventResult.handled;
  }

  Future<void> _consider(Accelerator accelerator) async {
    final serial = ++_serial;
    if (!accelerator.isUsableGlobally) {
      setState(() {
        _captured = null;
        _problem =
            '${accelerator.label} would get in the way of typing. '
            'Add Ctrl, Alt, or Super.';
      });
      return;
    }
    setState(() {
      _captured = accelerator;
      _problem = null;
      _checking = true;
    });
    String? problem;
    try {
      final conflict = await ref
          .read(shortcutServiceProvider)
          .findConflict(accelerator);
      if (conflict != null) {
        problem =
            '${accelerator.label} is already used by '
            '${conflict.description}.';
      }
    } on ShortcutException catch (error) {
      problem = 'Could not check for conflicts: ${error.message}.';
    }
    if (!mounted || serial != _serial) {
      return;
    }
    setState(() {
      _problem = problem;
      _checking = false;
    });
  }

  bool get _canSave => _captured != null && _problem == null && !_checking;

  Future<void> _save() async {
    final accelerator = _captured;
    if (accelerator == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final conflict = await ref
          .read(shortcutControllerProvider.notifier)
          .change(accelerator);
      if (!mounted) {
        return;
      }
      if (conflict != null) {
        setState(() {
          _saving = false;
          _problem =
              '${accelerator.label} is already used by '
              '${conflict.description}.';
        });
        return;
      }
      Navigator.of(context).pop();
    } on ShortcutException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _problem = 'Could not save the shortcut: ${error.message}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final captured = _captured;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: const Text('Set shortcut'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Press the keys you want to use. Esc cancels, Enter saves.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                liveRegion: true,
                label: captured == null
                    ? 'Waiting for keys'
                    : 'Shortcut ${captured.label}',
                child: ExcludeSemantics(
                  child: Container(
                    key: const Key('shortcut-capture'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xl,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadii.surface),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      captured?.label ?? 'Waiting for keys…',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: captured == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              if (_problem != null) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _problem!,
                    key: const Key('shortcut-problem'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('shortcut-cancel'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('shortcut-save'),
            onPressed: _canSave && !_saving ? _save : null,
            child: const Text('Set shortcut'),
          ),
        ],
      ),
    );
  }
}
