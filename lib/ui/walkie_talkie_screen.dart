import 'package:flutter/material.dart';
import 'package:vanilink/services/speech_to_text_service.dart';
import 'package:vanilink/services/language_router.dart';
import 'package:vanilink/services/vad_service.dart';

class WalkieTalkieScreen extends StatefulWidget {
  const WalkieTalkieScreen({Key? key}) : super(key: key);

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen> {
  // Instantiate your teammate's master service facade
  final SpeechToTextService _sttService = SpeechToTextService();
  
  bool _isListening = false;
  String _latestTranscript = "Press and hold to speak";
  double _speechProbability = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeSttPipeline();
  }

  Future<void> _initializeSttPipeline() async {
    // 1. Initialize all models in memory
    await _sttService.init();

    // 2. Set default language (e.g., Hindi uses IndicConformer, English uses Vosk)
    _sttService.setLanguage(AppLanguage.hindi);

    // 3. Listen to real-time transcribed text stream
    _sttService.transcriptionStream.listen((String transcribedText) {
      setState(() {
        _latestTranscript = transcribedText;
      });
      
      // TODO: Pass this text string to:
      // - Your P2P Network Manager (`P2PManager().sendTranscript(transcribedText)`)
      // - Your chat history ledger
    });

    // 4. Listen to VAD states for live UI wave/volume visualizers[cite: 3]
    _sttService.speechProbabilityStream.listen((double probability) {
      setState(() {
        _speechProbability = probability;
      });
    });
  }

  void _onPressDown() async {
    setState(() => _isListening = true);
    await _sttService.startListening(); // Triggers VAD and mic capture[cite: 3]
  }

  void _onPressUp() async {
    setState(() => _isListening = false);
    await _sttService.stopListening(); // Flushes buffers and finalizes transcription[cite: 3]
  }

  @override
  void dispose() {
    _sttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VaniLink - iTantra Core')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Live Probability Visualizer Indicator
          LinearProgressIndicator(value: _speechProbability),
          const SizedBox(height: 20),
          Text(_latestTranscript, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 40),
          GestureDetector(
            onTapDown: (_) => _onPressDown(),
            onTapUp: (_) => _onPressUp(),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? Colors.red : Colors.blue,
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 50),
            ),
          ),
        ],
      ),
    );
  }
}
