import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:vanilink/services/stt_engine_interface.dart';
import 'package:vanilink/services/vad_service.dart';

/// Offline English STT engine powered by sherpa-onnx.
/// Loads `assets/models/stt/english/model.onnx` + `tokens.txt`.
/// Implements [SttEngineInterface] identically to [IndicConformerSttEngine].
class VoskSttEngine implements SttEngineInterface {
  final String encoderAssetPath;
  final String decoderAssetPath;
  final String tokensAssetPath;
  final int numThreads;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  bool _isInitialized = false;

  VoskSttEngine({
    this.encoderAssetPath = 'assets/models/stt/english/tiny.en-encoder.int8.onnx',
    this.decoderAssetPath = 'assets/models/stt/english/tiny.en-decoder.int8.onnx',
    this.tokensAssetPath = 'assets/models/stt/english/tiny.en-tokens.txt',
    this.numThreads = 2,
  });

  @override
  bool get isInitialized => _isInitialized;

  Future<String> _extractAsset(String assetPath) async {
    final appDocDir = await getApplicationCacheDirectory();
    final file = File('${appDocDir.path}/${assetPath.split('/').last}');
    if (!file.existsSync()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final encoderPath = await _extractAsset(encoderAssetPath);
      final decoderPath = await _extractAsset(decoderAssetPath);
      final tokensPath = await _extractAsset(tokensAssetPath);

      final config = sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          whisper: sherpa_onnx.OfflineWhisperModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
          ),
          tokens: tokensPath,
          numThreads: numThreads,
          debug: false,
          provider: 'cpu',
        ),
      );

      _recognizer = sherpa_onnx.OfflineRecognizer(config);
      _isInitialized = true;
      debugPrint('VoskSttEngine (English/sherpa-onnx) initialized.');
    } catch (e) {
      _isInitialized = false;
      debugPrint('VoskSttEngine init note: $e');
      rethrow;
    }
  }

  @override
  Future<String> transcribeSegment(SpeechSegment segment) async {
    if (segment.samples.isEmpty) return '';
    if (!_isInitialized || _recognizer == null) {
      throw StateError('VoskSttEngine not initialized. Call init() first.');
    }
    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      stream.free();
      return result.text.trim();
    } catch (e) {
      debugPrint('VoskSttEngine transcription error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    try {
      _recognizer?.free();
    } catch (_) {}
    _recognizer = null;
    _isInitialized = false;
    debugPrint('VoskSttEngine disposed.');
  }
}
