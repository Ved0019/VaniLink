import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vanilink/ui/main_layout.dart';
import 'speech_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize speech models (STT & TTS) on app startup
  try {
    await SpeechService().initModels();
    debugPrint('✅ App initialized with speech models');
  } catch (e) {
    debugPrint('⚠️ Warning: Speech models not loaded: $e');
  }

  runApp(const VaniLinkApp());
}

class VaniLinkApp extends StatelessWidget {
  const VaniLinkApp({super.key});

  // Define the custom light theme matching user's previous setup
  static ThemeData _buildLightTheme() {
    final ThemeData base = ThemeData.light();
    return base.copyWith(
      // Use Google Fonts Manrope as the base typography
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.manrope(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
        displayMedium: GoogleFonts.manrope(
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        displaySmall: GoogleFonts.manrope(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        headlineLarge: GoogleFonts.manrope(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        headlineSmall: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        titleMedium: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        titleSmall: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: GoogleFonts.manrope(
          fontSize: 16,
        ),
        bodyMedium: GoogleFonts.manrope(
          fontSize: 14,
        ),
        bodySmall: GoogleFonts.manrope(
          fontSize: 12,
        ),
        labelLarge: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        labelMedium: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        labelSmall: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      // Color scheme based on user's UI pages
      colorScheme: const ColorScheme.light(
        primary: Colors.black87,
        secondary: Color(0xFFBBE5D9), // Mint green from UI pages
        surface: Color(0xFFF3F4F6), // Light gray background
      ),
      // Card theme
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
      ),
      // App bar theme
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      // Floating action button theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.black87,
      ),
      // Input decoration theme (for text fields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withAlpha(204),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaniLink',
      theme: _buildLightTheme(),
      home: const MainLayout(),
    );
  }
}