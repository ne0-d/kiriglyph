import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/theme/app_theme.dart';

void main() {
  test('light and dark themes use Material 3 and Ubuntu font stack', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = buildAppThemeForBrightness(brightness);
      expect(theme.useMaterial3, isTrue);
      expect(theme.textTheme.bodyMedium?.fontFamily, appFontFamily);
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    }
  });

  test('interactive controls meet minimum target and focus ring width', () {
    final theme = buildAppThemeForBrightness(Brightness.light);
    final filled = theme.filledButtonTheme.style;
    final min = filled?.minimumSize?.resolve({});
    expect(min, isNotNull);
    expect(min!.width, greaterThanOrEqualTo(AppA11y.minTapTarget));
    expect(min.height, greaterThanOrEqualTo(AppA11y.minTapTarget));

    final focusedSide = filled?.side?.resolve({WidgetState.focused});
    expect(focusedSide?.width, AppA11y.focusRingWidth);
    expect(focusedSide?.color, theme.colorScheme.primary);

    final iconMin = theme.iconButtonTheme.style?.minimumSize?.resolve({});
    expect(iconMin!.width, greaterThanOrEqualTo(AppA11y.minTapTarget));
    expect(iconMin.height, greaterThanOrEqualTo(AppA11y.minTapTarget));
  });

  test('KiriglyphThemeOptions can inject accent later', () {
    const accent = Color(0xFF0066CC);
    final theme = buildAppThemeForBrightness(
      Brightness.light,
      options: const KiriglyphThemeOptions(accentColor: accent),
    );
    expect(theme.colorScheme.primary, accent);
  });
}
