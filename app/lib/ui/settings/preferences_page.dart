import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/background/autostart.dart';
import 'package:kiriglyph/background/shortcut_pause.dart';
import 'package:kiriglyph/capture/instant_capture.dart';
import 'package:kiriglyph/overlay/selection_overlay.dart';
import 'package:kiriglyph/settings/app_settings.dart';
import 'package:kiriglyph/settings/folder_picker.dart';
import 'package:kiriglyph/shortcut/shortcut_controller.dart';
import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/tray/status_notifier.dart';
import 'package:kiriglyph/ui/settings/settings_widgets.dart';
import 'package:kiriglyph/ui/settings/shortcut_dialog.dart';

/// The normal window: first-run setup and preferences in one page. The
/// product itself is the overlay the shortcut opens.
class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notice = ref.watch(selectionNoticeProvider);
    final label = ref
        .watch(shortcutControllerProvider)
        .asData
        ?.value
        .binding
        ?.accelerator
        .label;
    final trayMissing =
        ref.watch(trayStateProvider).host == TrayHostState.missing;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kiriglyph',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label == null
                      ? 'Select and copy text from anything on your screen.'
                      : 'Press $label anywhere to select text or cut out an '
                            'object.',
                  key: const Key('intro'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (notice != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SettingsBanner(
                    key: const Key('selection-notice'),
                    message: notice,
                    tone: SettingsBannerTone.error,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                const SettingsGroup(
                  title: 'Capture',
                  children: [_ScreenAccessRow(), _ShortcutRow()],
                ),
                const SizedBox(height: AppSpacing.xl),
                const SettingsGroup(
                  title: 'Files',
                  children: [_SaveLocationRow()],
                ),
                const SizedBox(height: AppSpacing.xl),
                SettingsGroup(
                  title: 'Background',
                  children: [
                    const _LaunchAtLoginRow(),
                    const _PauseShortcutRow(),
                    if (trayMissing)
                      const SettingsRow(
                        title: 'Top-bar icon',
                        subtitle:
                            'No tray host found. Enable the AppIndicators '
                            'extension to get the Kiriglyph menu in the top bar.',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: FilledButton.icon(
                    key: const Key('try-selection'),
                    onPressed: () =>
                        ref.read(selectionOverlayProvider.notifier).start(),
                    icon: const Icon(Icons.screenshot_monitor_outlined),
                    label: const Text('Try it now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenAccessRow extends ConsumerStatefulWidget {
  const _ScreenAccessRow();

  @override
  ConsumerState<_ScreenAccessRow> createState() => _ScreenAccessRowState();
}

class _ScreenAccessRowState extends ConsumerState<_ScreenAccessRow> {
  bool _requesting = false;
  InstantCaptureStatus? _status;

  Future<void> _request() async {
    if (_requesting) {
      return;
    }
    setState(() {
      _requesting = true;
      _status = null;
    });
    InstantCaptureStatus status;
    try {
      status = await ref.read(instantCaptureProvider).requestPermission();
    } catch (_) {
      status = InstantCaptureStatus.failed;
    }
    if (!mounted) {
      return;
    }
    if (status == InstantCaptureStatus.granted) {
      ref.read(selectionNoticeProvider.notifier).clear();
    }
    await ref
        .read(appSettingsProvider.notifier)
        .setScreenAccessGranted(status == InstantCaptureStatus.granted);
    if (mounted) {
      setState(() {
        _requesting = false;
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final granted =
        ref.watch(appSettingsProvider).asData?.value.screenAccessGranted ??
        false;
    if (granted && !_requesting) {
      return SettingsRow(
        title: 'Screen access',
        subtitle: 'Allowed. Captures run silently.',
        trailing: Semantics(
          label: 'Allowed',
          child: Icon(Icons.check_circle, color: scheme.primary),
        ),
      );
    }
    final problem = _status != null && _status != InstantCaptureStatus.granted;
    final subtitle = switch ((_requesting, _status)) {
      (true, _) => 'Requesting screen access…',
      (_, InstantCaptureStatus.denied) =>
        'It was declined, or this window was not focused. Try again, or '
            'change it in Settings → Apps → Kiriglyph.',
      (_, InstantCaptureStatus.unavailable) =>
        'The GNOME screenshot portal is unavailable. Enable it, then try '
            'again.',
      (_, InstantCaptureStatus.failed) =>
        'Could not enable it. Try again from this window.',
      _ =>
        'Kiriglyph captures the screen when you press the shortcut. GNOME '
            'asks you once.',
    };
    return SettingsRow(
      title: 'Screen access',
      subtitle: subtitle,
      subtitleColor: problem ? scheme.error : null,
      trailing: FilledButton(
        key: const Key('enable-instant-capture'),
        onPressed: _requesting ? null : _request,
        child: _requesting
            ? SizedBox.square(
                dimension: AppSpacing.lg,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : Text(problem ? 'Try again' : 'Allow'),
      ),
    );
  }
}

class _ShortcutRow extends ConsumerWidget {
  const _ShortcutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shortcut = ref.watch(shortcutControllerProvider);
    final state = shortcut.asData?.value;

    if (shortcut.isLoading) {
      return const SettingsRow(title: 'Shortcut', subtitle: 'Checking…');
    }
    if (state?.error != null) {
      return const _ManualShortcutRow();
    }
    final binding = state?.binding;
    return SettingsRow(
      title: 'Shortcut',
      subtitle: binding == null
          ? 'Not set'
          : state!.addedAutomatically
          ? '${binding.accelerator.label}, added for you'
          : binding.accelerator.label,
      subtitleColor: binding == null ? theme.colorScheme.error : null,
      trailing: binding == null
          ? FilledButton(
              key: const Key('change-shortcut'),
              onPressed: () => _change(context),
              child: const Text('Set shortcut…'),
            )
          : OutlinedButton(
              key: const Key('change-shortcut'),
              onPressed: () => _change(context),
              child: const Text('Change…'),
            ),
    );
  }

  void _change(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const ShortcutDialog(),
    );
  }
}

/// Shown when GNOME's keyboard settings cannot be reached: the old manual
/// route, with the command ready to copy.
class _ManualShortcutRow extends ConsumerStatefulWidget {
  const _ManualShortcutRow();

  @override
  ConsumerState<_ManualShortcutRow> createState() => _ManualShortcutRowState();
}

class _ManualShortcutRowState extends ConsumerState<_ManualShortcutRow> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final command = ref.watch(selectionCommandProvider);
    return SettingsRow(
      title: 'Shortcut',
      subtitle:
          'Kiriglyph could not set it for you. In Settings → Keyboard → '
          'Custom Shortcuts, add one that runs:',
      subtitleColor: theme.colorScheme.error,
      details: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          children: [
            Flexible(
              child: SelectableText(
                command,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: appMonoFontFamily,
                  fontFamilyFallback: appMonoFontFallback,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              key: const Key('copy-selection-command'),
              tooltip: _copied ? 'Copied' : 'Copy command',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: command));
                if (mounted) {
                  setState(() => _copied = true);
                }
              },
              icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveLocationRow extends ConsumerStatefulWidget {
  const _SaveLocationRow();

  @override
  ConsumerState<_SaveLocationRow> createState() => _SaveLocationRowState();
}

class _SaveLocationRowState extends ConsumerState<_SaveLocationRow> {
  String? _error;

  Future<void> _choose() async {
    final picked = await ref
        .read(folderPickerProvider)
        .chooseFolder(current: ref.read(saveDirectoryProvider));
    if (!mounted || picked == null) {
      return;
    }
    if (!await canWriteTo(picked)) {
      if (mounted) {
        setState(() => _error = 'Kiriglyph cannot save files in that folder.');
      }
      return;
    }
    setState(() => _error = null);
    await ref.read(appSettingsProvider.notifier).setSaveDirectory(picked);
  }

  Future<void> _reset() async {
    setState(() => _error = null);
    await ref.read(appSettingsProvider.notifier).setSaveDirectory(null);
  }

  static String _short(String path) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty && path.startsWith('$home/')) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final custom =
        ref.watch(appSettingsProvider).asData?.value.saveDirectory != null;
    final directory = ref.watch(saveDirectoryProvider);
    return SettingsRow(
      title: 'Save location',
      subtitle: _error ?? _short(directory),
      subtitleColor: _error == null ? null : scheme.error,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (custom)
            TextButton(
              key: const Key('reset-save-folder'),
              onPressed: _reset,
              child: const Text('Reset'),
            ),
          OutlinedButton(
            key: const Key('choose-save-folder'),
            onPressed: _choose,
            child: const Text('Choose…'),
          ),
        ],
      ),
    );
  }
}

class _LaunchAtLoginRow extends ConsumerWidget {
  const _LaunchAtLoginRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launch = ref.watch(launchAtLoginProvider);
    void toggle(bool enabled) =>
        ref.read(launchAtLoginProvider.notifier).setEnabled(enabled);
    final value = launch.asData?.value ?? false;
    return SettingsRow(
      title: 'Launch at login',
      subtitle: launch.hasError
          ? 'Could not update this setting.'
          : 'Start hidden in the background so the shortcut is ready.',
      subtitleColor: launch.hasError
          ? Theme.of(context).colorScheme.error
          : null,
      onTap: launch.isLoading ? null : () => toggle(!value),
      trailing: Switch(
        key: const Key('launch-at-login'),
        value: value,
        onChanged: launch.isLoading ? null : toggle,
      ),
    );
  }
}

class _PauseShortcutRow extends ConsumerWidget {
  const _PauseShortcutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paused = ref.watch(shortcutPauseProvider);
    void set(bool value) =>
        ref.read(shortcutPauseProvider.notifier).setPaused(value);
    return SettingsRow(
      title: 'Pause shortcut',
      subtitle: 'Ignore the shortcut until you turn this off.',
      onTap: () => set(!paused),
      trailing: Switch(
        key: const Key('pause-shortcut'),
        value: paused,
        onChanged: set,
      ),
    );
  }
}
