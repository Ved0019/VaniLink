import 'package:flutter/material.dart';
import 'ui/walkie_talkie_screen.dart';
// import 'speech_service.dart'; // Uncomment when ready to init

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // TODO: Await SpeechService().initModels() here once models are downloaded
  
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