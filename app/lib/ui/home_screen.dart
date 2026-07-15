import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';
import 'package:ubuntu_live_text/ui/capture_surface.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(captureSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Text'),
        actions: [
          if (session.phase == CapturePhase.ready)
            TextButton(
              onPressed: () =>
                  ref.read(captureSessionProvider.notifier).reset(),
              child: const Text('New image'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _Body(session: session),
      ),
      floatingActionButton: session.phase == CapturePhase.recognizing
          ? null
          : FloatingActionButton.extended(
              key: const Key('open-image-fab'),
              onPressed: () =>
                  ref.read(captureSessionProvider.notifier).openImage(),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Open image'),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.session});

  final CaptureSessionState session;

  @override
  Widget build(BuildContext context) {
    switch (session.phase) {
      case CapturePhase.idle:
        return const _EmptyState(
          title: 'Open an image',
          detail: 'Choose a photo or screenshot to recognize text locally.',
        );
      case CapturePhase.recognizing:
        return const _RecognizingState();
      case CapturePhase.error:
        return _ErrorState(message: session.userMessage ?? 'Local OCR failed.');
      case CapturePhase.ready:
        final path = session.imagePath;
        final result = session.ocrResult;
        if (path == null || result == null) {
          return const _ErrorState(message: 'Something went wrong. Try again.');
        }
        return _ResultLayout(imagePath: path, ocrResult: result);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecognizingState extends StatelessWidget {
  const _RecognizingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 16),
          Text(
            'Local OCR',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not recognize text',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultLayout extends StatelessWidget {
  const _ResultLayout({required this.imagePath, required this.ocrResult});

  final String imagePath;
  final OcrResult ocrResult;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: CaptureSurface(imagePath: imagePath, ocrResult: ocrResult),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Recognized text',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AppColors.muted, letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
          SelectableText(
            ocrResult.fullText,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(height: 1.5, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
