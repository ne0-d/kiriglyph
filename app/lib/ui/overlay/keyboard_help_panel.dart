import 'package:flutter/material.dart';

import 'package:kiriglyph/a11y/keyboard_shortcuts.dart';
import 'package:kiriglyph/theme/app_theme.dart';

/// The keyboard cheat sheet: every shortcut and the keyboard alternative to
/// each pointer gesture. The overlay opens it with `?`, Ctrl+? or F1 and
/// closes it with Escape.
class KeyboardHelpPanel extends StatelessWidget {
  const KeyboardHelpPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Semantics(
      key: const Key('keyboard-help-semantics'),
      container: true,
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: 'Keyboard shortcuts',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Material(
              key: const Key('keyboard-help-panel'),
              color: colors.surfaceContainerHigh,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.surface),
                side: BorderSide(
                  color: highContrast ? colors.onSurface : colors.outline,
                  width: highContrast ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: FocusScope(
                autofocus: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.sm,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Keyboard shortcuts',
                              style: text.titleMedium,
                            ),
                          ),
                          IconButton(
                            key: const Key('keyboard-help-close'),
                            autofocus: true,
                            tooltip: 'Close (Esc)',
                            onPressed: onClose,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        key: const Key('keyboard-help-list'),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final group in keyboardShortcutGroups)
                              _Section(
                                title: group.title,
                                entries: group.entries,
                              ),
                            const _Section(
                              title: 'Without a pointer',
                              entries: pointerAlternatives,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.entries});

  final String title;
  final List<ShortcutEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: text.labelLarge?.copyWith(color: colors.primary),
            ),
          ),
          for (final entry in entries)
            Semantics(
              label: '${entry.keys}: ${entry.action}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        border: Border.all(color: colors.outline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        child: Text(
                          entry.keys,
                          style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Text(entry.action, style: text.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
