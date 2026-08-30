import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class MicrophoneHandler {
  static final MicrophoneHandler _instance = MicrophoneHandler._internal();
  factory MicrophoneHandler() => _instance;
  MicrophoneHandler._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSubscription;
  
  // Temporarily stores the audio chunks while the button is held down
  final List<int> _audioBuffer = [];

  /// Requests hardware microphone permissions from the OS
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Starts capturing 16kHz PCM audio and saving it to the buffer
  Future<void> startRecordingStream() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    _audioBuffer.clear();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1, 
    );

    final stream = await _audioRecorder.startStream(config);
    
    // Listen to the stream and append incoming bytes to our buffer
    _streamSubscription = stream.listen((Uint8List data) {
      _audioBuffer.addAll(data);
    });
  }

  /// Stops recording and returns the complete audio buffer
  Future<Uint8List> stopRecordingAndGetBuffer() async {
    await _audioRecorder.stop();
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    
    // Convert the list back into a raw byte array
    final finalBytes = Uint8List.fromList(_audioBuffer);
    _audioBuffer.clear();
    
    return finalBytes;
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}
