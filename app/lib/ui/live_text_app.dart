import 'package:flutter/material.dart';

import 'package:ubuntu_live_text/theme/app_theme.dart';
import 'package:ubuntu_live_text/ui/home_screen.dart';

class LiveTextApp extends StatelessWidget {
  const LiveTextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Text',
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
