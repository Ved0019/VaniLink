import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vanilink/ui/communication_page.dart';
import 'package:vanilink/ui/mapping_page.dart';
import 'package:vanilink/ui/network_page.dart';
import 'package:vanilink/ui/walkie_talkie_screen.dart';
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
      colorScheme: ColorScheme.light(
        primary: Colors.black87,
        secondary: Color(0xFFBBE5D9), // Mint green from UI pages
        surface: const Color(0xFFF3F4F6), // Light gray background
        background: const Color(0xFFF3F4F6),
      ),
      // Card theme
      cardTheme: CardTheme(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
      ),
      // App bar theme
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.black87,
      ),
      // Input decoration theme (for text fields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.8),
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
      home: const HomePage(),
      routes: {
        '/communication': (context) => const CommunicationPage(),
        '/mapping': (context) => const MappingPage(),
        '/network': (context) => const NetworkPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No app bar - clean look as per user's preference
      body: Container(
        color: Theme.of(context).colorScheme.background,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  'Welcome to VaniLink',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Offline peer-to-peer communication with location sharing',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 24,
                    children: [
                      _buildHomeCard(
                        context,
                        icon: Icons.chat_bubble_outline,
                        title: 'Communication',
                        subtitle: 'Real-time voice translation and transcription',
                        onTap: () {
                          Navigator.pushNamed(context, '/communication');
                        },
                      ),
                      _buildHomeCard(
                        context,
                        icon: Icons.map_outlined,
                        title: 'Mapping',
                        subtitle: 'See peer locations and track movements',
                        onTap: () {
                          Navigator.pushNamed(context, '/mapping');
                        },
                      ),
                      _buildHomeCard(
                        context,
                        icon: Icons.people_outline,
                        title: 'Network',
                        subtitle: 'Disconnect and connect with nearby peers',
                        onTap: () {
                          Navigator.pushNamed(context, '/network');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Default to communication page for PTT
          Navigator.pushNamed(context, '/communication');
        },
        label: const Text('Talk'),
        icon: const Icon(Icons.mic),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildHomeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}