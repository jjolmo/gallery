import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(AppScope(state: state, child: const GalleryApp()));
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  static const _seed = Color(0xFF4A8FE7);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return MaterialApp(
      title: 'Gallery',
      debugShowCheckedModeBanner: false,
      themeMode: app.themeMode,
      theme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
      // Mouse drags must swipe pages too on desktop Linux.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      home: const HomeScreen(),
    );
  }
}
