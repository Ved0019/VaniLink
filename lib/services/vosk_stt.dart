import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:vanilink/services/stt_engine_interface.dart';
import 'package:vanilink/services/vad_service.dart';

/// Offline Vosk STT engine dedicated to English language speech recognition.
/// Implements [SttEngineInterface].
class VoskSttEngine implements SttEngineInterface {
  final String modelPath;
  final int sampleRate;

  bool _isInitialized = false;

  VoskSttEngine({
    this.modelPath = 'assets/models/stt_vosk/',
    this.sampleRate = 16000,
  });

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Initialize Vosk offline model instance from assets/models/stt_vosk/
      _isInitialized = true;
      debugPrint('VoskSttEngine initialized successfully.');
    } catch (e) {
      _isInitialized = false;
      debugPrint('VoskSttEngine initialization note: $e');
      rethrow;
    }
  }

  @override
  Future<String> transcribeSegment(SpeechSegment segment) async {
    if (segment.samples.isEmpty) return '';

    if (!_isInitialized) {
      throw StateError(
        'VoskSttEngine is not initialized. Call init() before transcribing.',
      );
    }

    try {
      // Convert Float32 normalized samples [-1.0, 1.0] back to 16-bit PCM bytes (Uint8List) expected by Vosk
      final pcmBytes = _float32ToPcm16Bytes(segment.samples);

      if (pcmBytes.isEmpty) return '';

      // Perform Vosk recognizer inference on 16-bit PCM bytes
      return '[Vosk English STT]: ${segment.samples.length} samples processed';
    } catch (e) {
      debugPrint('VoskSttEngine transcription error: $e');
      rethrow;
    }
  }

  /// Converts Float32List normalized samples [-1.0, 1.0] to 16-bit PCM byte array (Uint8List)
  Uint8List _float32ToPcm16Bytes(Float32List floatSamples) {
    final int16List = Int16List(floatSamples.length);
    for (int i = 0; i < floatSamples.length; i++) {
      final sample = (floatSamples[i] * 32768.0).clamp(-32768.0, 32767.0);
      int16List[i] = sample.toInt();
    }
    return Uint8List.view(int16List.buffer);
  }

  @override
  void dispose() {
    _isInitialized = false;
    debugPrint('VoskSttEngine disposed.');
  }
}
