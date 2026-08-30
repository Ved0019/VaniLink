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

  /// Initializes STT and TTS models from bundled assets
  Future<void> initModels() async {
    try {
      // CRITICAL: Must initialize the sherpa-onnx C++ bindings first!
      sherpa_onnx.initBindings();

      // Extract STT model from assets
      final sttModelPath = await _extractAsset('assets/models/stt/indic/model.int8.onnx');
      final sttTokensPath = await _extractAsset('assets/models/stt/indic/tokens.txt');

      // Initialize STT Engine (Sherpa-ONNX NeMo CTC)
      try {
        _sttEngine = sherpa_onnx.OfflineRecognizer(
          sherpa_onnx.OfflineRecognizerConfig(
            model: sherpa_onnx.OfflineModelConfig(
              nemoCtc: sherpa_onnx.OfflineNemoEncDecCtcModelConfig(
                model: sttModelPath,
              ),
              tokens: sttTokensPath,
              numThreads: 1,
              debug: true,
            ),
          ),
        );
        print('✅ STT model initialized successfully');
      } catch (e) {
        print('⚠️ STT model initialization failed: $e');
        rethrow;
      }

      // Extract and Initialize TTS Engine (Sherpa-ONNX OfflineTts)
      try {
        final ttsModelPath = await _extractAsset('assets/models/tts/en/model.onnx');
        final ttsTokensPath = await _extractAsset('assets/models/tts/en/tokens.txt');
        final ttsDataZipPath = await _extractAsset('assets/models/tts/en/espeak-ng-data.zip');
        final ttsDataDir = ttsDataZipPath.replaceAll('.zip', '');

        _ttsEngine = sherpa_onnx.OfflineTts(
          sherpa_onnx.OfflineTtsConfig(
            model: sherpa_onnx.OfflineTtsModelConfig(
              vits: sherpa_onnx.OfflineTtsVitsModelConfig(
                model: ttsModelPath,
                tokens: ttsTokensPath,
                dataDir: ttsDataDir,
              ),
              numThreads: 1,
              debug: false,
            ),
          ),
        );
        print('✅ TTS model initialized successfully');
      } catch (e) {
        print('⚠️ TTS model initialization failed: $e');
      }

      _isInitialized = true;
      print('✅ Speech services initialized successfully');
    } catch (e) {
      print('❌ Error initializing speech models: $e');
      rethrow;
    }
  }

  /// Extracts asset from bundle to app cache directory
  Future<String> _extractAsset(String assetPath) async {
    try {
      final appDocDir = await getApplicationCacheDirectory();
      final file = File('${appDocDir.path}/${assetPath.split('/').last}');

      // Only extract if file doesn't exist
      if (!file.existsSync()) {
        final data = await rootBundle.load(assetPath);
        await file.writeAsBytes(data.buffer.asUint8List());
      }

      return file.path;
    } catch (e) {
      throw Exception('Failed to extract asset $assetPath: $e');
    }
  }

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