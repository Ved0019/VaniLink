import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' hide SpeechSegment;
import 'package:vanilink/services/stt_engine_interface.dart';
import 'package:vanilink/services/vad_service.dart';

/// Offline IndicConformer INT8 STT engine powered by sherpa_onnx.
/// Implements [SttEngineInterface] for Indian language speech recognition.
class IndicConformerSttEngine implements SttEngineInterface {
  final String modelPath;
  final String tokensPath;
  final int numThreads;

  OfflineRecognizer? _recognizer;
  bool _isInitialized = false;

  IndicConformerSttEngine({
    this.modelPath = 'assets/models/stt/model.int8.onnx',
    this.tokensPath = 'assets/models/stt/tokens.txt',
    this.numThreads = 2,
  });

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    final sttConfig = OfflineRecognizerConfig(
      model: OfflineModelConfig(
        nemoCtc: OfflineNemoEncDecCtcModelConfig(
          model: modelPath,
        ),
        tokens: tokensPath,
        numThreads: numThreads,
        debug: false,
        provider: 'cpu',
      ),
    );

    try {
      _recognizer = OfflineRecognizer(sttConfig);
      _isInitialized = true;
      debugPrint('IndicConformerSttEngine initialized successfully.');
    } catch (e) {
      _isInitialized = false;
      debugPrint('IndicConformerSttEngine initialization note: $e');
      rethrow;
    }
  }

  @override
  Future<String> transcribeSegment(SpeechSegment segment) async {
    if (segment.samples.isEmpty) return '';

    if (!_isInitialized || _recognizer == null) {
      throw StateError(
        'IndicConformerSttEngine is not initialized. Call init() before transcribing.',
      );
    }

    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
      _recognizer!.decode(stream);

      final result = _recognizer!.getResult(stream);
      final transcribedText = result.text.trim();

      stream.free();
      return transcribedText;
    } catch (e) {
      debugPrint('Error transcribing audio segment: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    try {
      _recognizer?.free();
    } catch (e) {
      debugPrint('Error disposing IndicConformerSttEngine: $e');
    }
    _recognizer = null;
    _isInitialized = false;
  }
}
