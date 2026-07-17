import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';

const _headerHeight = 56.0;
const _compactBreakpoint = 560.0;

/// Compact application bar: identity, current file and status, and the
/// explicit Open / New image controls.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(captureSessionProvider);
    final controller = ref.read(captureSessionProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < _compactBreakpoint;
    final canOpen = session.phase != CapturePhase.recognizing;

    return Material(
      color: AppColors.aubergine,
      child: SizedBox(
        height: _headerHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
          child: Row(
            children: [
              _Identity(compact: compact),
              SizedBox(width: compact ? 12 : 20),
              Expanded(child: _FileStatus(session: session)),
              const SizedBox(width: 12),
              if (session.phase == CapturePhase.recognizing) ...[
                if (compact)
                  IconButton(
                    key: const Key('cancel-recognition'),
                    tooltip: 'Cancel recognition',
                    onPressed: controller.cancelRecognition,
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  TextButton(
                    key: const Key('cancel-recognition'),
                    onPressed: controller.cancelRecognition,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Cancel'),
                  ),
                const SizedBox(width: 8),
              ],
              if (session.phase == CapturePhase.error &&
                  session.imagePath != null) ...[
                if (compact)
                  IconButton(
                    key: const Key('retry-recognition'),
                    tooltip: 'Retry recognition',
                    onPressed: controller.retry,
                    color: Colors.white,
                    icon: const Icon(Icons.refresh_rounded),
                  )
                else
                  TextButton(
                    key: const Key('retry-recognition'),
                    onPressed: controller.retry,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Retry'),
                  ),
                const SizedBox(width: 8),
              ],
              if (session.phase == CapturePhase.ready) ...[
                if (compact)
                  IconButton(
                    key: const Key('new-image'),
                    tooltip: 'New image',
                    onPressed: controller.reset,
                    color: Colors.white,
                    icon: const Icon(Icons.restart_alt_rounded),
                  )
                else
                  TextButton(
                    key: const Key('new-image'),
                    onPressed: controller.reset,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('New image'),
                  ),
                const SizedBox(width: 8),
              ],
              FilledButton.icon(
                key: const Key('open-image-fab'),
                onPressed: canOpen ? controller.openImage : null,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Open image'),
              ),
            ],
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
      label: 'Live Text',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.text_fields_rounded,
              color: AppColors.ubuntuOrange,
              size: 22,
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              const Text(
                'Live Text',
                style: TextStyle(
                  color: Colors.white,
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

class _FileStatus extends StatelessWidget {
  const _FileStatus({required this.session});

  final CaptureSessionState session;

  @override
  Widget build(BuildContext context) {
    final path = session.imagePath;
    final title = path == null ? 'No image open' : fileNameOf(path);
    final status = switch (session.phase) {
      CapturePhase.idle => 'Choose an image to recognize its text',
      CapturePhase.recognizing => 'Recognizing…',
      CapturePhase.ready => 'Recognized on this device',
      CapturePhase.error => 'Recognition failed',
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// The last path segment of [path].
String fileNameOf(String path) {
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final slash = trimmed.lastIndexOf('/');
  return slash < 0 ? trimmed : trimmed.substring(slash + 1);
}
