import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/ocr/ocr_result.dart';
import 'package:ubuntu_live_text/theme/app_theme.dart';
import 'package:ubuntu_live_text/ui/region_overlay.dart';

class CaptureSurface extends StatelessWidget {
  const CaptureSurface({
    super.key,
    required this.imagePath,
    required this.ocrResult,
  });

  final String imagePath;
  final OcrResult ocrResult;

  @override
  Widget build(BuildContext context) {
    final aspect = ocrResult.imageWidth / ocrResult.imageHeight;

    return AspectRatio(
      aspectRatio: aspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (kIsWeb)
            const ColoredBox(color: AppColors.background)
          else if (Platform.environment.containsKey('FLUTTER_TEST'))
            const ColoredBox(color: Color(0xFFE8E8E6))
          else
            Image.file(
              File(imagePath),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
          for (final region in ocrResult.regions)
            RegionOverlay(
              region: region,
              imageWidth: ocrResult.imageWidth,
              imageHeight: ocrResult.imageHeight,
            ),
        ],
      ),
    );
  }
}
