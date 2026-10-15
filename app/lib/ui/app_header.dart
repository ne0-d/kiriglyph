import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_shell.dart';

const _headerHeight = 56.0;
const _compactBreakpoint = 560.0;

/// Compact application bar for the setup window: identity and quit.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < _compactBreakpoint;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surface,
      child: SizedBox(
        height: _headerHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
            child: Row(
              children: [
                _Identity(compact: compact),
                const Spacer(),
                if (compact)
                  IconButton(
                    key: const Key('quit-app'),
                    tooltip: 'Quit Kiriglyph',
                    onPressed: () => ref.read(appShellProvider).requestQuit(),
                    icon: const Icon(Icons.logout_rounded),
                  )
                else
                  TextButton.icon(
                    key: const Key('quit-app'),
                    onPressed: () => ref.read(appShellProvider).requestQuit(),
                    icon: const Icon(Icons.logout_rounded, size: 18),
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
  const _Identity({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Kiriglyph',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.text_fields_rounded,
              color: Color(0xFFE95420),
              size: 22,
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(
                'Kiriglyph',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
