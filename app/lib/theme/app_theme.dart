import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Ubuntu orange: primary actions and selected OCR regions only.
  static const ubuntuOrange = Color(0xFFE95420);

  /// Workspace chrome accent used over the dark image-inspection surface.
  static const aubergine = Color(0xFF2C2027);

  /// Dark image-inspection surface.
  static const canvas = Color(0xFF201C1F);

  /// Recognized-text panel.
  static const paper = Color(0xFFFFFFFF);

  /// Workspace row background for unselected recognized text.
  static const shell = Color(0xFFF4F2F1);

  static const muted = Color(0xFF71676B);
  static const ink = Color(0xFF241F20);

  /// Hairline separators on paper and shell.
  static const hairline = Color(0xFFE2DDDB);
}

/// System Ubuntu font where available, with sensible desktop fallbacks.
const appFontFamily = 'Ubuntu Sans';
const appFontFallback = [
  'Ubuntu',
  'Cantarell',
  'Noto Sans',
  'DejaVu Sans',
  'sans-serif',
];

ThemeData buildAppTheme(ThemeData base) {
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFallback,
    ),
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(
      color: base.colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: base.colorScheme.onSurface,
      selectionColor: base.colorScheme.primary.withValues(alpha: 0.32),
    ),
  );
}
