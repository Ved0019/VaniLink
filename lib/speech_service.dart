import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Singleton service that owns STT + TTS sherpa-onnx engines.
/// Multi-language TTS is lazy-loaded per language to minimize RAM.
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  sherpa_onnx.OfflineRecognizer? _sttEngine;
  sherpa_onnx.OfflineTts? _ttsEngine;

  String _currentTtsLang = 'en';
  bool _sttReady = false;
  bool _ttsReady = false;

  bool get isInitialized => _sttReady;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────

  /// Initializes STT (IndicConformer) and the default English TTS model.
  Future<void> initModels() async {
    sherpa_onnx.initBindings();

    // ── STT ──────────────────────────────────────────────────────────────
    try {
      final sttModelPath =
          await _extractAsset('assets/models/stt/indic/model.int8.onnx');
      final sttTokensPath =
          await _extractAsset('assets/models/stt/indic/tokens.txt');

      _sttEngine = sherpa_onnx.OfflineRecognizer(
        sherpa_onnx.OfflineRecognizerConfig(
          model: sherpa_onnx.OfflineModelConfig(
            nemoCtc: sherpa_onnx.OfflineNemoEncDecCtcModelConfig(
              model: sttModelPath,
            ),
            tokens: sttTokensPath,
            numThreads: 2,
            debug: false,
            provider: 'cpu',
          ),
        ),
      );
      _sttReady = true;
    } catch (e) {
      // STT unavailable — app degrades gracefully
      _sttReady = false;
    }

    // ── TTS (default: English) ───────────────────────────────────────────
    await _loadTts('en');
  }

  /// Lazy-loads a TTS engine for the given ISO language code.
  /// Unloads the previous engine if the language changes (saves RAM).
  Future<void> setTtsLanguage(String langCode) async {
    if (_currentTtsLang == langCode && _ttsReady) return;
    await _loadTts(langCode);
  }

  Future<void> _loadTts(String langCode) async {
    _ttsEngine?.free();
    _ttsEngine = null;
    _ttsReady = false;
    _currentTtsLang = langCode;

    try {
      final modelPath =
          await _extractAsset('assets/models/tts/$langCode/model.onnx');
      final tokensPath =
          await _extractAsset('assets/models/tts/$langCode/tokens.txt');

      // Extract the espeak-ng-data zip into a real directory
      final dataDir = await _extractEspeakData(langCode);

      _ttsEngine = sherpa_onnx.OfflineTts(
        sherpa_onnx.OfflineTtsConfig(
          model: sherpa_onnx.OfflineTtsModelConfig(
            vits: sherpa_onnx.OfflineTtsVitsModelConfig(
              model: modelPath,
              tokens: tokensPath,
              dataDir: dataDir,
            ),
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      _ttsReady = true;
    } catch (e) {
      // TTS unavailable for this language — not fatal
      debugPrint('TTS load failed for $langCode: $e');
      _ttsReady = false;
    }
  }

  /// Extracts `espeak-ng-data.zip` from assets into the app cache directory.
  /// Returns the path to the extracted `espeak-ng-data/` folder.
  Future<String> _extractEspeakData(String langCode) async {
    final dir = await getApplicationCacheDirectory();
    final extractedDir = Directory('${dir.path}/espeak-ng-data-$langCode');

    // Skip extraction if already done
    if (extractedDir.existsSync() && extractedDir.listSync().isNotEmpty) {
      return extractedDir.path;
    }

    // Extract zip from assets to a temp file, then unzip it
    final zipAssetPath = 'assets/models/tts/$langCode/espeak-ng-data.zip';
    final zipFile = File('${dir.path}/espeak-ng-data-$langCode.zip');
    final data = await rootBundle.load(zipAssetPath);
    await zipFile.writeAsBytes(data.buffer.asUint8List());

    // Decompress
    extractedDir.createSync(recursive: true);
    final zipBytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive.files) {
      if (file.isFile) {
        final outFile = File('${extractedDir.path}/${file.name}');
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      }
    }


    // Clean up zip
    await zipFile.delete();
    return extractedDir.path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inference
  // ─────────────────────────────────────────────────────────────────────────

  /// Transcribes raw 16 kHz PCM bytes to text.
  String transcribeAudio(Uint8List rawBytes, {int sampleRate = 16000}) {
    if (!_sttReady || _sttEngine == null) {
      throw Exception('STT engine not initialized');
    }
    final pcm = _bytesToFloat32(rawBytes);
    final stream = _sttEngine!.createStream();
    stream.acceptWaveform(sampleRate: sampleRate, samples: pcm);
    _sttEngine!.decode(stream);
    final result = _sttEngine!.getResult(stream);
    stream.free();
    return result.text.trim();
  }

  /// Converts text to Float32 audio samples ready for [TtsPlayer].
  /// Returns an empty list if TTS is not initialized (graceful degradation).
  Float32List synthesizeSpeech(String text, {double speed = 1.0}) {
    if (!_ttsReady || _ttsEngine == null) {
      return Float32List(0); // Graceful degradation
    }
    final audio = _ttsEngine!.generate(text: text, sid: 0, speed: speed);
    return audio.samples;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _extractAsset(String assetPath) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/${assetPath.split('/').last}');
    if (!file.existsSync()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  Float32List _bytesToFloat32(Uint8List bytes) {
    final int16 = Int16List.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
    final f32 = Float32List(int16.length);
    for (int i = 0; i < int16.length; i++) {
      f32[i] = int16[i] / 32768.0;
    }
    return f32;
  }

  void dispose() {
    _sttEngine?.free();
    _ttsEngine?.free();
    _sttReady = false;
    _ttsReady = false;
  }
}
