import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  sherpa_onnx.OfflineRecognizer? _sttEngine;
  sherpa_onnx.OfflineTts? _ttsEngine;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // ... (Keep your _extractAsset, _extractAndUnzip, and initModels methods here exactly as we wrote them earlier) ...

  /// Converts 16-bit PCM raw bytes into normalized Float32 samples for Sherpa-ONNX
  Float32List _convertBytesToFloat32(Uint8List bytes) {
    final int16List = Int16List.view(
      bytes.buffer, 
      bytes.offsetInBytes, 
      bytes.lengthInBytes ~/ 2,
    );
    
    final float32List = Float32List(int16List.length);
    for (int i = 0; i < int16List.length; i++) {
      float32List[i] = int16List[i] / 32768.0;
    }
    
    return float32List;
  }

  /// Converts raw 16kHz PCM audio bytes from PTT mic to text
  String transcribeAudio(Uint8List rawBytes, {int sampleRate = 16000}) {
    if (!_isInitialized || _sttEngine == null) {
      throw Exception('STT Engine is not initialized');
    }

    final pcmSamples = _convertBytesToFloat32(rawBytes);

    final stream = _sttEngine!.createStream();
    stream.acceptWaveform(sampleRate: sampleRate, samples: pcmSamples);
    _sttEngine!.decode(stream);

    final result = _sttEngine!.getResult(stream);
    stream.free();
    
    return result.text.trim();
  }

  /// Converts received text payload into raw PCM audio samples for playback
  Float32List synthesizeSpeech(String text, {double speed = 1.0}) {
    if (!_isInitialized || _ttsEngine == null) {
      throw Exception('TTS Engine is not initialized');
    }

    final audio = _ttsEngine!.generate(text: text, sid: 0, speed: speed);
    return audio.samples; // Fixed the null-assertion warning here
  }

  void dispose() {
    _sttEngine?.free();
    _ttsEngine?.free();
    _isInitialized = false;
  }
}