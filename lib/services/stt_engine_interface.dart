import 'package:vanilink/services/vad_service.dart';

/// Common abstraction interface for offline Speech-To-Text engines (IndicConformer, Vosk, etc.)
abstract class SttEngineInterface {
  /// Initializes the STT engine model into RAM
  Future<void> init();

  /// Engine initialization status
  bool get isInitialized;

  /// Transcribes a 16 kHz Float32 PCM SpeechSegment to text
  Future<String> transcribeSegment(SpeechSegment segment);

  /// Releases native memory resources
  void dispose();
}
