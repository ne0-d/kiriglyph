import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  bool _requesting = false;
  bool _commandCopied = false;
  InstantCaptureStatus? _status;

  Future<void> _requestPermission() async {
    if (_requesting) {
      return;
    }
    setState(() {
      _requesting = true;
      _status = null;
    });
    try {
      final status = await ref.read(instantCaptureProvider).requestPermission();
      if (!mounted) {
        return;
      }
      if (status == InstantCaptureStatus.granted) {
        ref.read(selectionNoticeProvider.notifier).clear();
      }
      setState(() => _status = status);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _status = InstantCaptureStatus.failed);
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  Future<void> _copyCommand(String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) {
      return;
    }
    setState(() => _commandCopied = true);
  }

  @override
  Widget build(BuildContext context) {
    final command = ref.watch(selectionCommandProvider);
    final notice = ref.watch(selectionNoticeProvider);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.text_fields_rounded, size: 36, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                'Set up Kiriglyph',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enable the shortcut flow to select and copy text anywhere on '
                'your Ubuntu desktop.',
                style: text.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.72),
                  height: 1.45,
                ),
              ),
              if (notice != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    notice,
                    key: const Key('selection-notice'),
                    style: text.bodyMedium?.copyWith(
                      color: colors.error,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                key: const Key('enable-instant-capture'),
                onPressed: _requesting ? null : _requestPermission,
                icon: _requesting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.screenshot_monitor_outlined),
                label: Text(
                  _requesting
                      ? 'Requesting screen access…'
                      : 'Enable instant capture',
                ),
              ),
              const SizedBox(height: 12),
              _PermissionMessage(requesting: _requesting, status: _status),
              const SizedBox(height: 28),
              _ShortcutSetup(
                command: command,
                copied: _commandCopied,
                onCopy: () => _copyCommand(command),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionMessage extends StatelessWidget {
  const _PermissionMessage({required this.requesting, required this.status});

  final bool requesting;
  final InstantCaptureStatus? status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = switch ((requesting, status)) {
      (true, _) => 'Requesting screen access…',
      (false, InstantCaptureStatus.granted) => 'Instant capture is enabled.',
      (false, InstantCaptureStatus.denied) =>
        'GNOME asked for screen access and it was declined, or this window '
            'was not focused. Retry here, or change it in Settings → Apps → '
            'Kiriglyph → Screenshots.',
      (false, InstantCaptureStatus.unavailable) =>
        'The screenshot portal is unavailable. Enable the GNOME screenshot '
            'portal, then retry.',
      (false, InstantCaptureStatus.failed) =>
        'Could not enable instant capture. Retry from this window.',
      _ => 'GNOME may ask once before shortcut captures can run silently.',
    };

    final color = switch ((requesting, status)) {
      (false, InstantCaptureStatus.granted) => colors.primary,
      (
        false,
        InstantCaptureStatus.denied ||
            InstantCaptureStatus.unavailable ||
            InstantCaptureStatus.failed,
      ) =>
        colors.error,
      _ => colors.onSurface.withValues(alpha: 0.72),
    };

    return Semantics(
      liveRegion: requesting || status != null,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: color, height: 1.4),
      ),
    );
  }
}

class _ShortcutSetup extends StatelessWidget {
  const _ShortcutSetup({
    required this.command,
    required this.copied,
    required this.onCopy,
  });

  final String command;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shortcut setup',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Settings → Keyboard → View and Customize Shortcuts → '
              'Custom Shortcuts → Add Shortcut',
            ),
            const SizedBox(height: 12),
            const Text('Name: Kiriglyph'),
            const SizedBox(height: 8),
            Text('Command', style: text.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(6),
                      color: colors.surface,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: SelectableText(
                        command,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('copy-selection-command'),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Choose a shortcut such as Super+Shift+T.',
              style: text.bodySmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.72),
              ),
            ),
            if (copied) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Command copied',
                  style: text.bodySmall?.copyWith(color: colors.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
