import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/settings/background_section.dart';

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
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set up Kiriglyph',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Enable the shortcut flow to select and copy text anywhere on '
                'your Ubuntu desktop.',
                style: text.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (notice != null) ...[
                const SizedBox(height: AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.section),
              Text(
                'Screen access',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'GNOME may ask once before shortcut captures can run silently.',
                style: text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('enable-instant-capture'),
                onPressed: _requesting ? null : _requestPermission,
                icon: _requesting
                    ? SizedBox.square(
                        dimension: AppSpacing.lg,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.screenshot_monitor_outlined),
                label: Text(
                  _requesting
                      ? 'Requesting screen access…'
                      : 'Enable instant capture',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _PermissionMessage(requesting: _requesting, status: _status),
              const SizedBox(height: AppSpacing.section),
              _ShortcutSetup(
                command: command,
                copied: _commandCopied,
                onCopy: () => _copyCommand(command),
              ),
              const SizedBox(height: AppSpacing.section),
              const BackgroundSection(),
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
      _ => null,
    };

    if (message == null) {
      return const SizedBox.shrink();
    }

    final color = switch ((requesting, status)) {
      (false, InstantCaptureStatus.granted) => colors.primary,
      (
        false,
        InstantCaptureStatus.denied ||
            InstantCaptureStatus.unavailable ||
            InstantCaptureStatus.failed,
      ) =>
        colors.error,
      _ => colors.onSurfaceVariant,
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
    final mono = text.bodyMedium?.copyWith(
      fontFamily: appMonoFontFamily,
      fontFamilyFallback: appMonoFontFallback,
      fontSize: 13,
    );

    return YaruSection(
      headline: const Text('Shortcut setup'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings → Keyboard → View and Customize Shortcuts → '
            'Custom Shortcuts → Add Shortcut',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Name: Kiriglyph', style: text.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('Command', style: text.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: YaruBorderContainer(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: SelectableText(command, style: mono),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('copy-selection-command'),
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Choose a shortcut such as Super+Shift+T.',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (copied) ...[
            const SizedBox(height: AppSpacing.sm),
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
    );
  }
}
