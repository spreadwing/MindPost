import 'package:flutter/material.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PostMcpApp());
}

class PostMcpApp extends StatelessWidget {
  const PostMcpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostMCP - AI-Native API Workbench',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFE2E8F0),
        fontFamily: 'Segoe UI',
      ),
      home: const HomeScreen(),
    );
  }
}
