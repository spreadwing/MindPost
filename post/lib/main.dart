import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/app_fonts.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      minimumSize: Size(960, 600),
      center: true,
      title: 'MindPost',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MindPostApp());
}

class MindPostApp extends StatelessWidget {
  const MindPostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindPost',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFE2E8F0),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8F0),
          space: 1,
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
          ),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        tabBarTheme: const TabBarThemeData(
          indicatorColor: Color(0xFF2563EB),
          labelColor: Color(0xFF2563EB),
          unselectedLabelColor: Color(0xFF64748B),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              TextStyle(fontSize: 12.5, fontWeight: FontWeight.normal),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 11),
          waitDuration: const Duration(milliseconds: 400),
        ),
        fontFamily: AppFonts.uiFamily,
        fontFamilyFallback: AppFonts.uiFallback,
      ),
      home: const HomeScreen(),
    );
  }
}
