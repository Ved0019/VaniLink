import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  sherpa_onnx.OfflineRecognizer? _sttEngine;
  sherpa_onnx.OfflineTts? _ttsEngine;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Helper function: Extracts bundled assets to the phone's physical storage
  Future<String> _extractAsset(String assetPath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final file = File('${docDir.path}/$assetPath');
    
    // Check if we already extracted it in a previous app launch
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    }
    return file.path;
  }

  /// Loads quantized ONNX models into device RAM for offline inference
  Future<void> initModels() async {
    if (_isInitialized) return;

    // 1. Initialize Sherpa-ONNX C++ Bindings
    sherpa_onnx.initBindings();

    // 2. Extract STT assets to local storage
    final sttModelPath = await _extractAsset('assets/models/stt/model.int8.onnx');
    final sttTokensPath = await _extractAsset('assets/models/stt/tokens.txt');

    // Configure STT using the physical device paths
    final sttConfig = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        nemoCtc: sherpa_onnx.OfflineNemoEncDecCtcModelConfig(
          model: sttModelPath,
        ),
        tokens: sttTokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    _sttEngine = sherpa_onnx.OfflineRecognizer(config: sttConfig);

    // 3. Extract TTS assets to local storage
    final ttsModelPath = await _extractAsset('assets/models/tts/model.onnx');
    final ttsTokensPath = await _extractAsset('assets/models/tts/tokens.txt');
    // Note: If espeak-ng-data is a directory, you will need to extract every file inside it.
    final ttsDataDir = await _extractAsset('assets/models/tts/espeak-ng-data'); 

    // Configure TTS using the physical device paths
    final ttsConfig = sherpa_onnx.OfflineTtsConfig(
      model: sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: ttsModelPath,
          tokens: ttsTokensPath,
          dataDir: ttsDataDir,
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    _ttsEngine = sherpa_onnx.OfflineTts(config: ttsConfig);

    _isInitialized = true;
  }

  /// Converts raw 16kHz PCM audio buffers from PTT mic to text
  String transcribeAudio(Float32List pcmSamples, {int sampleRate = 16000}) {
    if (!_isInitialized || _sttEngine == null) {
      throw Exception('STT Engine is not initialized');
    }

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
    return audio.samples;
  }

  void dispose() {
    _sttEngine?.free();
    _ttsEngine?.free();
    _isInitialized = false;
  }
}