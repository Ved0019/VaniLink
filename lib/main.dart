import 'package:flutter/material.dart';
import 'ui/walkie_talkie_screen.dart';
import 'speech_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize speech models (STT & TTS) on app startup
  try {
    await SpeechService().initModels();
    print('✅ App initialized with speech models');
  } catch (e) {
    print('⚠️ Warning: Speech models not loaded: $e');
  }
  
  runApp(const VaniLinkApp());
}

class VaniLinkApp extends StatelessWidget {
  const VaniLinkApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaniLink',
      theme: ThemeData.dark(useMaterial3: true),
      home: const WalkieTalkieScreen(),
    );
  }
}