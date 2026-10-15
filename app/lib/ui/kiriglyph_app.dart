import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'package:kiriglyph/theme/app_theme.dart';
import 'package:kiriglyph/ui/home_screen.dart';

class KiriglyphApp extends StatelessWidget {
  const KiriglyphApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      data: const YaruThemeData(
        themeMode: ThemeMode.system,
        visualDensity: VisualDensity.compact,
      ),
      builder: (context, yaru, child) {
        return MaterialApp(
          title: 'Kiriglyph',
          theme: buildAppTheme(yaru.theme),
          darkTheme: buildAppTheme(yaru.darkTheme),
          themeMode: yaru.themeMode ?? ThemeMode.system,
          home: const HomeScreen(),
        );
      },
    );
  }
}
