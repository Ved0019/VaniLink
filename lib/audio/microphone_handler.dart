import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class MicrophoneHandler {
  // Use a singleton pattern so we don't accidentally open multiple mic streams
  static final MicrophoneHandler _instance = MicrophoneHandler._internal();
  factory MicrophoneHandler() => _instance;
  MicrophoneHandler._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  Stream<Uint8List>? _audioStream;

  /// Requests hardware microphone permissions from the OS
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Starts streaming raw PCM audio bytes into memory
  Future<Stream<Uint8List>?> startRecordingStream() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    // CRITICAL: Sherpa-ONNX requires exactly 16kHz, mono-channel, 16-bit PCM.
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1, 
    );

    // This creates a continuous stream of audio chunks (Uint8List)
    _audioStream = await _audioRecorder.startStream(config);
    return _audioStream;
  }

  /// Stops the hardware microphone
  Future<void> stopRecording() async {
    await _audioRecorder.stop();
    _audioStream = null;
  }

  /// Releases the hardware resources when the app closes
  void dispose() {
    _audioRecorder.dispose();
  }
}