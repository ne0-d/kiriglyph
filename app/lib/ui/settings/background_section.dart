import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/background/autostart.dart';
import 'package:kiriglyph/tray/status_notifier.dart';

class BackgroundSection extends ConsumerWidget {
  const BackgroundSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launchAtLogin = ref.watch(launchAtLoginProvider);
    final tray = ref.watch(trayStateProvider);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Background app', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Keep Kiriglyph ready for the selection shortcut and top-bar menu.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Launch at login'),
              subtitle: const Text('Starts hidden in the background.'),
              value: launchAtLogin.asData?.value ?? false,
              onChanged: launchAtLogin.isLoading
                  ? null
                  : (enabled) {
                      ref
                          .read(launchAtLoginProvider.notifier)
                          .setEnabled(enabled);
                    },
            ),
            if (launchAtLogin.hasError)
              Text(
                'Could not update launch at login.',
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            if (tray.host == TrayHostState.missing) ...[
              const SizedBox(height: 8),
              Text(
                'No top-bar host found; use the shortcut or the launcher.',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
