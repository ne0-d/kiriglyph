import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/home_screen.dart';

class KiriglyphApp extends StatelessWidget {
  const KiriglyphApp({
    super.key,
    this.themeOptions = const KiriglyphThemeOptions(),
  });

  /// Optional accent override; [YaruTheme] supplies GNOME accent when unset.
  final KiriglyphThemeOptions themeOptions;

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      data: const YaruThemeData(themeMode: ThemeMode.system),
      builder: (context, yaru, child) {
        return MaterialApp(
          title: 'Kiriglyph',
          theme: buildAppTheme(yaru.theme, options: themeOptions),
          darkTheme: buildAppTheme(yaru.darkTheme, options: themeOptions),
          themeMode: yaru.themeMode ?? ThemeMode.system,
          home: const HomeScreen(),
        );
      },
    );
  }
}
