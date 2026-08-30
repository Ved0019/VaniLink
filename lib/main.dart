import 'package:flutter/material.dart';
import 'ui/walkie_talkie_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaniLink',
      theme: ThemeData.dark(useMaterial3: true),
      home: const EditorialWalkieTalkieScreen(),
    );
  }
}
