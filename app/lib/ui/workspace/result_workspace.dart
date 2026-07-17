import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';
import 'package:ubuntu_live_text/ui/workspace/capture_canvas.dart';
import 'package:ubuntu_live_text/ui/workspace/recognized_text_panel.dart';

const _splitMinWidth = 720.0;
const _splitMinWidthWhenShort = 480.0;
const _shortHeight = 480.0;
const _panelMinWidth = 320.0;
const _panelMaxWidth = 440.0;
const _stackedPanelMinHeight = 200.0;

/// Responsive split workspace: image-inspection canvas beside the recognized
/// text panel, stacked vertically in narrow windows.
class ResultWorkspace extends StatelessWidget {
  const ResultWorkspace({
    super.key,
    required this.imagePath,
    required this.ocrResult,
  });

  final String imagePath;
  final OcrResult ocrResult;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = CaptureCanvas(
          imagePath: imagePath,
          ocrResult: ocrResult,
        );
        final panel = RecognizedTextPanel(ocrResult: ocrResult);

        // A short window is better served side by side even when narrow,
        // because a stacked panel would be too short to use.
        final split =
            constraints.maxWidth >= _splitMinWidth ||
            (constraints.maxHeight < _shortHeight &&
                constraints.maxWidth >= _splitMinWidthWhenShort);

        if (split) {
          final panelWidth = (constraints.maxWidth * 0.34).clamp(
            _panelMinWidth,
            _panelMaxWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: canvas),
              SizedBox(
                width: panelWidth,
                child: _Bordered(side: _Side.left, child: panel),
              ),
            ],
          );
        }

        final panelHeight = (constraints.maxHeight * 0.4).clamp(
          _stackedPanelMinHeight,
          double.infinity,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: canvas),
            SizedBox(
              height: panelHeight,
              child: _Bordered(side: _Side.top, child: panel),
            ),
          ],
        );
      },
    );
  }
}

enum _Side { left, top }

class _Bordered extends StatelessWidget {
  const _Bordered({required this.side, required this.child});

  final _Side side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const line = BorderSide(color: AppColors.hairline);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: switch (side) {
          _Side.left => const Border(left: line),
          _Side.top => const Border(top: line),
        },
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 0),
          ),
        ],
      ),
      child: child,
    );
  }
}
