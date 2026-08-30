import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' hide SpeechSegment;
import 'package:vanilink/services/stt_engine_interface.dart';
import 'package:vanilink/services/vad_service.dart';

/// Offline IndicConformer INT8 STT engine powered by sherpa_onnx.
///
/// Automatically detects the correct model format by trying config types
/// in order: ZipformerCTC → NemoCtc → WenetCtc.
/// This is necessary because different sherpa-onnx builds ship IndicConformer
/// in different formats. Each attempt is caught gracefully.
class IndicConformerSttEngine implements SttEngineInterface {
  final String modelAssetPath;
  final String tokensAssetPath;
  final int numThreads;

  OfflineRecognizer? _recognizer;
  bool _isInitialized = false;
  String _detectedFormat = 'unknown';

  IndicConformerSttEngine({
    this.modelAssetPath = 'assets/models/stt/indic/model.int8.onnx',
    this.tokensAssetPath = 'assets/models/stt/indic/tokens.txt',
    this.numThreads = 2,
  });

  @override
  bool get isInitialized => _isInitialized;

  String get detectedFormat => _detectedFormat;

  Future<String> _extract(String assetPath) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/${assetPath.split('/').last}');
    if (!file.existsSync()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    final modelPath = await _extract(modelAssetPath);
    final tokensPath = await _extract(tokensAssetPath);

    // Try each known IndicConformer format in order.
    // sherpa-onnx logs a C++ warning and throws on format mismatch —
    // we catch each and move to the next candidate.
    final candidates = <(String, OfflineRecognizerConfig)>[
      _cfgZipformerCtc(modelPath, tokensPath),
      _cfgNemoCtc(modelPath, tokensPath),
      _cfgWenetCtc(modelPath, tokensPath),
      _cfgTdnn(modelPath, tokensPath),
    ];

    for (final (label, config) in candidates) {
      try {
        final r = OfflineRecognizer(config);
        _recognizer = r;
        _isInitialized = true;
        _detectedFormat = label;
        debugPrint('IndicConformerSttEngine: initialized as $label ✅');
        return;
      } catch (e) {
        debugPrint('IndicConformerSttEngine: $label failed ($e)');
      }
    }

    debugPrint(
      'IndicConformerSttEngine: ⚠️ No matching config found for this model.\n'
      'Download a compatible sherpa-onnx Indic model from:\n'
      'https://github.com/k2-fsa/sherpa-onnx/releases\n'
      'Look for: sherpa-onnx-nemo-ctc-ai4bharat-indicconformer-*',
    );
    // Engine stays disabled — transcription returns empty string gracefully.
  }

  // ── Config builders (using correct sherpa_onnx 1.13.x API) ────────────────

  (String, OfflineRecognizerConfig) _cfgZipformerCtc(String m, String t) =>
      (
        'ZipformerCtc',
        OfflineRecognizerConfig(
          model: OfflineModelConfig(
            zipformerCtc: OfflineZipformerCtcModelConfig(model: m),
            tokens: t,
            numThreads: numThreads,
            debug: false,
            provider: 'cpu',
          ),
        ),
      );

  (String, OfflineRecognizerConfig) _cfgNemoCtc(String m, String t) =>
      (
        'NemoEncDecCtc',
        OfflineRecognizerConfig(
          model: OfflineModelConfig(
            nemoCtc: OfflineNemoEncDecCtcModelConfig(model: m),
            tokens: t,
            numThreads: numThreads,
            debug: false,
            provider: 'cpu',
          ),
        ),
      );

  (String, OfflineRecognizerConfig) _cfgWenetCtc(String m, String t) =>
      (
        'WenetCtc',
        OfflineRecognizerConfig(
          model: OfflineModelConfig(
            wenetCtc: OfflineWenetCtcModelConfig(model: m),
            tokens: t,
            numThreads: numThreads,
            debug: false,
            provider: 'cpu',
          ),
        ),
      );

  (String, OfflineRecognizerConfig) _cfgTdnn(String m, String t) =>
      (
        'Tdnn',
        OfflineRecognizerConfig(
          model: OfflineModelConfig(
            tdnn: OfflineTdnnModelConfig(model: m),
            tokens: t,
            numThreads: numThreads,
            debug: false,
            provider: 'cpu',
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<String> transcribeSegment(SpeechSegment segment) async {
    if (segment.samples.isEmpty) return '';
    if (!_isInitialized || _recognizer == null) return '';

    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(sampleRate: 16000, samples: segment.samples);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      stream.free();
      return result.text.trim();
    } catch (e) {
      debugPrint('IndicConformerSttEngine transcription error: $e');
      return '';
    }
  }

  @override
  void dispose() {
    try {
      _recognizer?.free();
    } catch (_) {}
    _recognizer = null;
    _isInitialized = false;
  }
}
