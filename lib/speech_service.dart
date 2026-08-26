import 'package:flutter/material.dart';
import 'speech_service.dart'; 

void main() async {
  // Ensure Flutter bindings are initialized before calling native code
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the offline STT and TTS models into memory
  final speechService = SpeechService();
  await speechService.initModels();
  
  runApp(const WalkieTalkieApp());
}

class WalkieTalkieApp extends StatelessWidget {
  const WalkieTalkieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTantra Walkie-Talkie',
      theme: ThemeData(
        // FIXED: Added 'ColorScheme' before '.fromSeed'
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const WalkieTalkieScreen(),
    );
  }
}

class WalkieTalkieScreen extends StatefulWidget {
  const WalkieTalkieScreen({super.key});

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen> {
  String _transcribedText = "Hold the button to speak...";
  bool _isRecording = false;

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _transcribedText = "Listening...";
    });
    // TODO: Trigger microphone capture thread and Silero VAD
  }

  void _stopRecording() {
    setState(() {
      _isRecording = false;
      _transcribedText = "Processing...";
    });
    // TODO: Stop recording and send the audio buffer to the local ASR engine
    
    /* Example implementation for when audio capture is hooked up:
       final text = SpeechService().transcribeAudio(pcmData);
       setState(() {
         _transcribedText = text;
       });
       // Then send `text` over Wi-Fi Direct socket.
    */
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Offline Walkie-Talkie'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _transcribedText,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      // A virtual Push-to-Talk (PTT) button to gate the microphone input
      floatingActionButton: GestureDetector(
        onTapDown: (_) => _startRecording(),
        onTapUp: (_) => _stopRecording(),
        onTapCancel: () => _stopRecording(),
        child: FloatingActionButton(
          onPressed: () {}, // Handled by GestureDetector
          backgroundColor: _isRecording ? Colors.red : Colors.teal,
          elevation: _isRecording ? 2 : 6,
          child: Icon(
            _isRecording ? Icons.mic : Icons.mic_none, 
            size: 32,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}