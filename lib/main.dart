import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  OfflineRecognizer? _sttEngine;
  OfflineTts? _ttsEngine;
  bool _isInitialized = false;
  OfflineLMConfig? = __ttsEngine;

  bool get isInitialized => _isInitialized;

  /// Loads quantized ONNX models into device RAM for offline inference
  Future<void> initModels() async {
    if (_isInitialized) return;

    // 1. Configure Offline STT (IndicConformer CTC / INT8)
    const sttConfig = OfflineRecognizerConfig(
      model: OfflineModelConfig(
        nemoCtc: OfflineNemoEncDecCtcModelConfig(
          model: 'assets/models/stt/model.int8.onnx',
        ),
        tokens: 'assets/models/stt/tokens.txt',
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    
    // Initialize STT engine with positionally passed config
    _sttEngine = OfflineRecognizer(sttConfig);

    // 2. Configure Offline TTS (Piper / MMS-TTS VITS engine)
    const ttsConfig = OfflineTtsConfig(
      model: OfflineTtsModelConfig(
        vits: OfflineTtsVitsModelConfig(
          model: 'assets/models/tts/model.onnx',
          tokens: 'assets/models/tts/tokens.txt',
          dataDir: 'assets/models/tts/espeak-ng-data',
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
    );
    
    // FIXED: Pass ttsConfig positionally without the 'config:' parameter name
    _ttsEngine = OfflineTts(ttsConfig);

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

    final audio = _ttsEngine!.generate(text: text, speed: speed);
    return audio.samples;
  }

  void dispose() {
    _sttEngine?.free();
    _ttsEngine?.free();
    _isInitialized = false;
  }
}