import 'dart:io';

import 'package:flutter/material.dart';

import 'package:kiriglyph/theme/app_theme.dart';

/// Under `flutter test` the real file is never decoded; a flat placeholder
/// keeps rendering deterministic and independent of fixture images.
bool get _isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');

/// The capture surface pixels. Always sized by its parent, which supplies the
/// exact `BoxFit.contain` destination rectangle shared with the OCR overlay.
class CaptureImage extends StatelessWidget {
  const CaptureImage({super.key, required this.imagePath, this.label});

  final String imagePath;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (_isFlutterTest) {
      image = const ColoredBox(color: Color(0xFFE8E8E6));
    } else {
      image = Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: AppColors.aubergine,
          child: Center(
            child: Text(
              'Preview unavailable',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      );
    }
    return Semantics(
      image: true,
      label: label ?? 'Image being recognized',
      child: image,
    );
  }
}
