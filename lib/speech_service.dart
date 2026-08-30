import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:archive/archive_io.dart'; // Required for unzip

/// Singleton service that owns STT + TTS sherpa-onnx engines.
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

  Future<void> initModels() async {
    sherpa_onnx.initBindings();

    // ── STT ──────────────────────────────────────────────────────────────
    try {
      final sttModelPath = await _extractAsset('assets/models/stt/indic/model.int8.onnx');
      final sttTokensPath = await _extractAsset('assets/models/stt/indic/tokens.txt');

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
      print('✅ STT (IndicConformer) initialized successfully');
    } catch (e) {
      print('⚠️ STT initialization failed. Offline transcription unavailable: $e');
      _sttReady = false;
    }

    // ── TTS (default: English) ───────────────────────────────────────────
    await _loadTts('en');
  }

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
      final modelPath = await _extractAsset('assets/models/tts/$langCode/model.onnx');
      final tokensPath = await _extractAsset('assets/models/tts/$langCode/tokens.txt');
      
      final dir = await getApplicationCacheDirectory();
      final espeakDataDir = Directory('${dir.path}/espeak-ng-data');
      
      // 1. FORCE CLEAN EXTRACTION
      // Delete the old corrupted extraction if it exists so we can do it right
      if (espeakDataDir.existsSync()) {
        espeakDataDir.deleteSync(recursive: true);
      }

      // Recreate the directory after deletion
      await espeakDataDir.create(recursive: true);
      
      print('📦 Extracting espeak-ng-data.zip securely...');
      final byteData = await rootBundle.load('assets/models/tts/$langCode/espeak-ng-data.zip');
      final bytes = byteData.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        String filename = file.name;
        // Normalize the path: strip the root folder name if the zip included it
        if (filename.startsWith('espeak-ng-data/')) {
          filename = filename.replaceFirst('espeak-ng-data/', '');
        }
        if (filename.isEmpty) continue;

        final outFile = File('${espeakDataDir.path}/$filename');
        if (file.isFile) {
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory('${espeakDataDir.path}/$filename').create(recursive: true);
        }
      }

      // 2. PRE-FLIGHT CHECK (Prevent C++ Crash)
      final testPhontab = File('${espeakDataDir.path}/phontab');
      final testModel = File(modelPath);
      
      if (!testPhontab.existsSync()) {
        print('❌ FATAL: espeak data extracted incorrectly. Phontab missing!');
        return; // Abort before C++ crashes the app
      }
      if (testModel.lengthSync() < 1000) {
        print('❌ FATAL: The TTS .onnx model is 0 bytes or corrupted!');
        return; // Abort before C++ crashes the app
      }

      print('✅ Pre-flight check passed. Booting C++ TTS Engine...');

      // 3. INITIALIZE TTS ENGINE
      _ttsEngine = sherpa_onnx.OfflineTts(
        sherpa_onnx.OfflineTtsConfig(
          model: sherpa_onnx.OfflineTtsModelConfig(
            vits: sherpa_onnx.OfflineTtsVitsModelConfig(
              model: modelPath,
              tokens: tokensPath,
              dataDir: espeakDataDir.path,
            ),
            numThreads: 1, 
            debug: false,
            provider: 'cpu', 
          ),
        ),
      );
      
      _ttsReady = true;
      print('✅ TTS ($langCode) initialized successfully');
    } catch (e) {
      print('⚠️ TTS initialization failed for language: $langCode');
      print('   Error: $e');
      _ttsReady = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inference
  // ─────────────────────────────────────────────────────────────────────────

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

  Float32List synthesizeSpeech(String text, {double speed = 1.0}) {
    if (!_ttsReady || _ttsEngine == null) {
      return Float32List(0);
    }
    final audio = _ttsEngine!.generate(text: text, sid: 0, speed: speed);
    return audio.samples;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _extractAsset(String assetPath) async {
    final dir = await getApplicationCacheDirectory();
    
    // FIX: Replace slashes with underscores so tokens.txt from STT and TTS don't overwrite each other!
    final safeFileName = assetPath.replaceAll('/', '_'); 
    final file = File('${dir.path}/$safeFileName');
    
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