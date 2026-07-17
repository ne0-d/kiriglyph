import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/capture/capture_session.dart';
import 'package:ubuntu_live_text/ui/app_header.dart';
import 'package:ubuntu_live_text/ui/status_views.dart';
import 'package:ubuntu_live_text/ui/workspace/result_workspace.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(captureSessionProvider);

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(child: _Body(session: session)),
        ],
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
        return const EmptyStateView();
      case CapturePhase.recognizing:
        return const RecognizingStateView();
      case CapturePhase.error:
        return ErrorStateView(
          message: session.userMessage ?? 'Local OCR failed.',
        );
      case CapturePhase.ready:
        final path = session.imagePath;
        final result = session.ocrResult;
        if (path == null || result == null) {
          return const ErrorStateView(
            message: 'Something went wrong. Try again.',
          );
        }
        return ResultWorkspace(imagePath: path, ocrResult: result);
    }
  }
}
