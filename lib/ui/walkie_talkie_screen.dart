import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../audio/microphone_handler.dart';
import '../speech_service.dart';

class WalkieTalkieScreen extends StatefulWidget {
  const WalkieTalkieScreen({Key? key}) : super(key: key);

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen> {
  bool _isRecording = false;
  String _lastTranscribedText = "Press and hold to speak";

  void _startRecording() async {
    setState(() => _isRecording = true);
    try {
      await MicrophoneHandler().startRecordingStream();
    } catch (e) {
      setState(() {
        _isRecording = false;
        _lastTranscribedText = "Error: $e";
      });
    }
  }

  void _stopRecording() async {
    if (!_isRecording) return;
    
    setState(() {
      _isRecording = false;
      _lastTranscribedText = "Transcribing...";
    });

    try {
      // 1. Get the recorded audio buffer
      final Uint8List audioBytes = await MicrophoneHandler().stopRecordingAndGetBuffer();
      
      // 2. Transcribe locally using the AI Engine
      if (SpeechService().isInitialized) {
        final String spokenText = SpeechService().transcribeAudio(audioBytes);
        setState(() {
          _lastTranscribedText = spokenText.isEmpty ? "No speech detected." : spokenText;
        });
      } else {
        setState(() {
          _lastTranscribedText = "AI models are still loading...";
        });
      }
    } catch (e) {
      setState(() => _lastTranscribedText = "Transcription failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VaniLink - Offline P2P')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              _lastTranscribedText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTapDown: (_) => _startRecording(),
            onTapUp: (_) => _stopRecording(),
            onTapCancel: () => _stopRecording(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isRecording ? 200 : 160,
              height: _isRecording ? 200 : 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? Colors.redAccent : Colors.blueAccent,
                boxShadow: [
                  if (_isRecording)
                    BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 30)
                ],
              ),
              child: const Icon(Icons.mic, size: 80, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}