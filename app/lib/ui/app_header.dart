import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/constants.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/theme/app_theme.dart';

const _compactBreakpoint = 560.0;

/// In-window toolbar below the GTK header bar: app identity and quit.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < _compactBreakpoint;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Material(
      color: colors.surface,
      child: SizedBox(
        height: kYaruAppBarHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(
                  alpha: colors.brightness == Brightness.light ? 1 : 0.6,
                ),
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.md : AppSpacing.page,
            ),
            child: Row(
              children: [
                _Identity(compact: compact, text: text, colors: colors),
                const Spacer(),
                if (compact)
                  IconButton(
                    key: const Key('quit-app'),
                    tooltip: 'Quit Kiriglyph',
                    onPressed: () => ref.read(appShellProvider).requestQuit(),
                    icon: Icon(Icons.close, color: colors.onSurface),
                  )
                else
                  TextButton.icon(
                    key: const Key('quit-app'),
                    onPressed: () => ref.read(appShellProvider).requestQuit(),
                    icon: Icon(Icons.close, color: colors.onSurface, size: 18),
                    label: const Text('Quit'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.compact,
    required this.text,
    required this.colors,
  });

  final bool compact;
  final TextTheme text;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Kiriglyph',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.text_snippet_outlined, color: colors.primary, size: 20),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Kiriglyph',
                style: text.titleMedium?.copyWith(color: colors.onSurface),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
