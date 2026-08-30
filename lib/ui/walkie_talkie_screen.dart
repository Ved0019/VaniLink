import 'package:flutter/material.dart';

class WalkieTalkieScreen extends StatefulWidget {
  const WalkieTalkieScreen({Key? key}) : super(key: key);

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen> {
  bool _isRecording = false;

  void _startRecording() {
    setState(() => _isRecording = true);
    // TODO: Call microphone_handler to start capturing 16kHz audio
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
    // TODO: Stop capture, pass to speech_service for STT, then broadcast via P2P
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VaniLink - Offline P2P')),
      body: Center(
        child: GestureDetector(
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
      ),
    );
  }
}