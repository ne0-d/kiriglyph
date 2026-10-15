import 'dart:async';

import 'package:kiriglyph/segmentation/subject_segmenter.dart';

class FakeSubjectSegmenter implements SubjectSegmenter {
  FakeSubjectSegmenter({
    SubjectMaskResult? result,
    this.embedDelay = Duration.zero,
    this.promptDelay = Duration.zero,
    this.embedError,
    this.promptError,
  }) : result = result ?? _defaultResult;

  final SubjectMaskResult result;
  final Duration embedDelay;
  final Duration promptDelay;
  final Object? embedError;
  final Object? promptError;
  bool closed = false;
  bool failCancelled = false;
  int embedCalls = 0;
  int promptCalls = 0;
  int cancelCalls = 0;
  final prompts = <SubjectPrompt>[];

  @override
  Future<SubjectEmbedding> embed(String imagePath) async {
    _checkOpen();
    embedCalls += 1;
    if (embedDelay > Duration.zero) {
      await Future<void>.delayed(embedDelay);
    }
    if (failCancelled) {
      throw const SubjectSegmentationException(
        kind: SubjectFailureKind.cancelled,
        message: 'subject segmentation was cancelled',
      );
    }
    final error = embedError;
    if (error != null) {
      throw error;
    }
    return const SubjectEmbedding(
      handle: 'fake-embedding',
      imageWidth: 10,
      imageHeight: 8,
      timings: SubjectSegmentationTimings(loadMs: 1, embedMs: 2),
    );
  }

  @override
  Future<SubjectMaskResult> prompt(
    SubjectEmbedding embedding,
    SubjectPrompt prompt,
  ) async {
    _checkOpen();
    promptCalls += 1;
    prompts.add(prompt);
    if (promptDelay > Duration.zero) {
      await Future<void>.delayed(promptDelay);
    }
    if (failCancelled) {
      throw const SubjectSegmentationException(
        kind: SubjectFailureKind.cancelled,
        message: 'subject segmentation was cancelled',
      );
    }
    final error = promptError;
    if (error != null) {
      throw error;
    }
    return result;
  }

  @override
  Future<void> cancelActive() async {
    cancelCalls += 1;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  void _checkOpen() {
    if (closed) {
      throw const SubjectSegmentationException(
        kind: SubjectFailureKind.sessionClosed,
        message: 'subject segmenter is closed',
      );
    }
  }
}

const _defaultResult = SubjectMaskResult(
  imageWidth: 10,
  imageHeight: 8,
  mask: SubjectMaskReference(
    path: '/tmp/fake-mask.png',
    byteLength: 1,
    sha256: '0',
  ),
  bounds: SubjectRect(x: 1, y: 1, width: 6, height: 5),
  stats: SubjectMaskStats(
    outcome: SubjectMaskOutcome.ok,
    areaFraction: 0.4,
    bounds: SubjectRect(x: 1, y: 1, width: 6, height: 5),
    touchesEdge: SubjectEdgeTouches(
      left: false,
      top: false,
      right: false,
      bottom: false,
    ),
    components: SubjectComponentStats(
      count: 1,
      largestBounds: SubjectRect(x: 1, y: 1, width: 6, height: 5),
    ),
  ),
  timings: SubjectSegmentationTimings(promptMs: 3),
  confidence: 0.8,
);
