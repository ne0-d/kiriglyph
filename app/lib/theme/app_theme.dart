import 'package:flutter/material.dart';
import 'package:yaru/constants.dart';

/// Optional overrides applied on top of [YaruTheme] (e.g. injected accent).
class KiriglyphThemeOptions {
  const KiriglyphThemeOptions({this.accentColor});

  /// When non-null, replaces [ColorScheme.primary] for both light and dark.
  final Color? accentColor;
}

/// Workspace and overlay-specific colours (not used by the setup window).
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

  /// Confirmation fill for "Copied" and "Saved" (white text is 5:1 on it).
  static const success = Color(0xFF1B7F4B);

  /// Selection neon: a saturated magenta that stays visible on light and
  /// dark screenshots and sits with the Ubuntu aubergine and orange chrome.
  static const neonMagenta = Color(0xFFFF2BD6);

  /// Second stop of the free-draw trail gradient.
  static const neonOrchid = Color(0xFFB65CFF);

  /// Hot centre of a neon stroke.
  static const neonCore = Color(0xFFFFEAFB);
}

/// GNOME / Yaru spacing grid for the setup window and shared layout math.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;

  /// Matches [kYaruPagePadding].
  static const page = kYaruPagePadding;
  static const xl = 24.0;
  static const section = 28.0;
}

/// Corner radii aligned with Yaru (8 px controls, 12 px grouped surfaces).
abstract final class AppRadii {
  static const control = kYaruButtonRadius;
  static const surface = kYaruContainerRadius;
}

/// Accessibility tokens shared with overlay widgets via [ThemeData] merges.
abstract final class AppA11y {
  /// Minimum interactive target (GNOME HIG / issue 25).
  static const minTapTarget = 24.0;

  /// Visible keyboard focus ring width (matches [kYaruFocusBorderWidth]).
  static const focusRingWidth = kYaruFocusBorderWidth;
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

/// Monospace stack for commands and snippets (system fonts, not bundled).
const appMonoFontFamily = 'Ubuntu Mono';
const appMonoFontFallback = ['Roboto Mono', 'Liberation Mono', 'monospace'];

const _minTapTargetSize = Size(AppA11y.minTapTarget, AppA11y.minTapTarget);

ThemeData buildAppTheme(
  ThemeData base, {
  KiriglyphThemeOptions options = const KiriglyphThemeOptions(),
}) {
  final scheme = options.accentColor == null
      ? base.colorScheme
      : base.colorScheme.copyWith(primary: options.accentColor);

  final textTheme = base.textTheme.apply(
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFallback,
  );

  final focusRingColor = scheme.primary;

  ButtonStyle augmentButtons(ButtonStyle? style) {
    return (style ?? const ButtonStyle()).copyWith(
      minimumSize: const WidgetStatePropertyAll(_minTapTargetSize),
      tapTargetSize: MaterialTapTargetSize.padded,
      side: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.focused)) {
          return null;
        }
        return BorderSide(color: focusRingColor, width: AppA11y.focusRingWidth);
      }),
    );
  }

  IconButtonThemeData augmentIconButtons(IconButtonThemeData? theme) {
    final style = theme?.style ?? IconButton.styleFrom();
    return IconButtonThemeData(
      style: augmentButtons(style).copyWith(
        minimumSize: const WidgetStatePropertyAll(_minTapTargetSize),
        fixedSize: null,
        maximumSize: null,
      ),
    );
  }

  return base.copyWith(
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.onSurface,
      selectionColor: scheme.primary.withValues(alpha: 0.32),
      selectionHandleColor: scheme.primary,
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.surface),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.surface),
      ),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      labelStyle: textTheme.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: augmentButtons(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: augmentButtons(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: augmentButtons(base.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: augmentButtons(base.elevatedButtonTheme.style),
    ),
    iconButtonTheme: augmentIconButtons(base.iconButtonTheme),
    focusColor: focusRingColor.withValues(alpha: 0.12),
    hoverColor: scheme.onSurface.withValues(alpha: 0.06),
    highlightColor: scheme.onSurface.withValues(alpha: 0.10),
  );
}

/// Builds light and dark [ThemeData] for tests and tooling (Yaru base required).
ThemeData buildAppThemeForBrightness(
  Brightness brightness, {
  KiriglyphThemeOptions options = const KiriglyphThemeOptions(),
}) {
  final seed = brightness == Brightness.dark
      ? const Color(0xFF777777)
      : const Color(0xFF333333);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.ubuntuOrange,
      brightness: brightness,
      primary: AppColors.ubuntuOrange,
      surface: seed,
    ),
  );
  return buildAppTheme(base, options: options);
}
