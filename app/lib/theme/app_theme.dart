import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF7F7F5);
  static const ink = Color(0xFF241F20);
  static const muted = Color(0xFF6F686A);
  static const ubuntuOrange = Color(0xFFE95420);
}

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    surface: AppColors.background,
    onSurface: AppColors.ink,
    primary: AppColors.ubuntuOrange,
    onPrimary: Colors.white,
    outline: AppColors.muted,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: Typography.material2021().black.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ubuntuOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
  );
}
