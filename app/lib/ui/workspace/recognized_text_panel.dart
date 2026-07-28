import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/selection/region_selection.dart';
import 'package:ubuntu_live_text/selection/region_selection_provider.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';
import 'package:ubuntu_live_text/ui/workspace/recognized_text_row.dart';

const _feedbackDuration = Duration(milliseconds: 2500);
const _copyFailedMessage = 'Could not copy. Try again.';

/// Paper panel: line count and OCR duration, persistent copy actions with
/// brief feedback, and the recognized lines as selectable text.
class RecognizedTextPanel extends ConsumerStatefulWidget {
  const RecognizedTextPanel({super.key, required this.ocrResult});

  final OcrResult ocrResult;

  @override
  ConsumerState<RecognizedTextPanel> createState() =>
      _RecognizedTextPanelState();
}

class _RecognizedTextPanelState extends ConsumerState<RecognizedTextPanel> {
  String? _feedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String text, String successMessage) async {
    var message = successMessage;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      message = _copyFailedMessage;
    }
    if (!mounted) {
      return;
    }
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(_feedbackDuration, () {
      if (mounted) {
        setState(() => _feedback = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(regionSelectionProvider);
    final lineCount = selection.regions.length;
    ref.listen(copySelectionRequestProvider, (previous, next) {
      final current = ref.read(regionSelectionProvider);
      if (next != previous && current.hasSelection) {
        _copy(current.selectedText, 'Copied ${_selectionAmount(current)}');
      }
    });

    return Column(
      key: const Key('text-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _PanelHeading(
            lineCount: lineCount,
            durationMs: widget.ocrResult.timingsMs.total,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('copy-selection'),
                onPressed: !selection.hasSelection
                    ? null
                    : () => _copy(
                        selection.selectedText,
                        'Copied ${_selectionAmount(selection)}',
                      ),
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                label: const Text('Copy selection'),
              ),
              OutlinedButton.icon(
                key: const Key('copy-all'),
                onPressed: lineCount == 0
                    ? null
                    : () => _copy(
                        selection.allText,
                        'Copied all ${_lines(lineCount)}',
                      ),
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Copy all'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            height: 18,
            child: Semantics(
              liveRegion: true,
              child: Text(
                _feedback ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _feedback == _copyFailedMessage
                      ? AppColors.ink
                      : AppColors.muted,
                ),
              ),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: lineCount == 0
              ? const _NoText()
              : _LineList(selection: selection),
        ),
      ],
    );
  }

  static String _lines(int count) => count == 1 ? '1 line' : '$count lines';

  static String _selectionAmount(RegionSelection selection) {
    final lines = selection.selectedRegions.length;
    if (lines > 0) {
      return _lines(lines);
    }
    final characters = selection.selectedCharacterCount;
    return characters == 1 ? '1 character' : '$characters characters';
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.lineCount, required this.durationMs});

  final int lineCount;
  final num durationMs;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        const Text(
          'Recognized text',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${lineCount == 1 ? '1 line' : '$lineCount lines'} · '
          '${formatDuration(durationMs)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ],
    );
  }
}

/// "420 ms" below one second, otherwise seconds with one decimal ("1.4 s").
String formatDuration(num milliseconds) {
  if (milliseconds < 1000) {
    return '${milliseconds.round()} ms';
  }
  return '${(milliseconds / 1000).toStringAsFixed(1)} s';
}

class _NoText extends StatelessWidget {
  const _NoText();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No text found',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Try an image with clearer or larger text.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineList extends StatelessWidget {
  const _LineList({required this.selection});

  final RegionSelection selection;

  @override
  Widget build(BuildContext context) {
    final regions = selection.regions;
    final numberWidth = '${regions.length}'.length * 8.0 + 4;

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < regions.length; i++)
              RecognizedTextRow(
                region: regions[i],
                number: i + 1,
                numberWidth: numberWidth,
              ),
          ],
        ),
      ),
    );
  }
}
