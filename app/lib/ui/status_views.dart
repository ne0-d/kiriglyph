import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/theme/app_theme.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: Icons.image_search_outlined,
      title: 'Open an image',
      detail:
          'Use Open image to choose a photo or screenshot. Text is '
          'recognized on this device and never uploaded.',
    );
  }
}

class RecognizingStateView extends StatelessWidget {
  const RecognizingStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        container: true,
        label: 'Recognizing text',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.ubuntuOrange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Local OCR',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Recognizing text on this device',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: Icons.error_outline_rounded,
      title: 'Could not recognize text',
      detail: message,
      liveRegion: true,
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.liveRegion = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Semantics(
            liveRegion: liveRegion,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32, color: AppColors.muted),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: theme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    height: 1.45,
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
