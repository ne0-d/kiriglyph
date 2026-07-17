import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Ubuntu orange: primary actions and selected OCR regions only.
  static const ubuntuOrange = Color(0xFFE95420);

  /// Header and application chrome.
  static const aubergine = Color(0xFF2C2027);

  /// Dark image-inspection surface.
  static const canvas = Color(0xFF201C1F);

  /// Recognized-text panel.
  static const paper = Color(0xFFFFFFFF);

  /// Window background behind the panels.
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

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    surface: AppColors.shell,
    onSurface: AppColors.ink,
    primary: AppColors.ubuntuOrange,
    onPrimary: Colors.white,
    secondary: AppColors.aubergine,
    outline: AppColors.muted,
    outlineVariant: AppColors.hairline,
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(4),
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
  const buttonText = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFallback,
    scaffoldBackgroundColor: AppColors.shell,
    textTheme: Typography.material2021().black.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    visualDensity: VisualDensity.compact,
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: AppColors.aubergine.withValues(alpha: 0.28),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ubuntuOrange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.hairline,
        disabledForegroundColor: AppColors.muted,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        disabledForegroundColor: AppColors.muted.withValues(alpha: 0.6),
        side: const BorderSide(color: AppColors.hairline),
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
  );
}
