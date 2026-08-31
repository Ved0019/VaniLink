import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vanilink/services/audio_capture_service.dart';
import 'package:vanilink/services/language_router.dart';
import 'package:vanilink/services/vad_service.dart';

/// Unified Speech-to-Text Service encapsulating:
/// Microphone Capture -> 30ms Chunking -> Silero VAD -> Audio Buffer -> Language Router -> STT Engine -> Transcribed Text
///
/// Designed as a clean interface for UI (Member 5), P2P Transceiver (Member 4), and Foreground Service (Member 6).
class SpeechToTextService {
  final AudioCaptureService _audioService;
  final VadService _vadService;
  final SttLanguageRouter _languageRouter;

  final StreamController<String> _transcriptionController =
      StreamController<String>.broadcast();

  StreamSubscription<SpeechSegment>? _segmentSubscription;
  bool _isInitialized = false;

  SpeechToTextService({
    AudioCaptureService? audioService,
    VadService? vadService,
    SttLanguageRouter? languageRouter,
  })  : _audioService = audioService ?? AudioCaptureService(),
        _vadService = vadService ?? VadService(),
        _languageRouter = languageRouter ?? SttLanguageRouter();

  /// Service initialization state
  bool get isInitialized => _isInitialized;

  /// Microphone listening state
  bool get isListening => _audioService.isRecording;

  /// Current target language
  AppLanguage get currentLanguage => _languageRouter.currentLanguage;

  /// Display name of active STT engine
  String get activeEngineName => _languageRouter.activeEngineName;

  /// Stream emitting continuous transcribed text strings
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  /// Stream emitting real-time VAD state transitions
  Stream<VadState> get vadStateStream => _vadService.vadStateStream;

  /// Stream emitting real-time speech probability scores (0.0 to 1.0)
  Stream<double> get speechProbabilityStream => _vadService.speechProbabilityStream;

  /// Stream emitting raw audio chunks (optional for visualization)
  Stream<Float32List> get audioChunkStream => _audioService.audioChunkStream;

  /// Initializes underlying STT models into device RAM
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _languageRouter.init();
      _isInitialized = true;
      debugPrint('SpeechToTextService initialized successfully.');
    } catch (e) {
      debugPrint('SpeechToTextService init note: $e');
      _isInitialized = true;
    }
  }

  /// Sets target language for STT routing
  void setLanguage(AppLanguage language) {
    _languageRouter.setLanguage(language);
  }

  /// Starts real-time 16 kHz microphone capture, VAD, and offline STT pipeline
  Future<void> startListening() async {
    if (isListening) return;

    if (!_isInitialized) {
      await init();
    }

    _vadService.reset();

    // Connect Audio Capture -> VAD
    _vadService.attachAudioStream(_audioService.audioChunkStream);

    // Listen for finalized speech segments from VAD -> Route to STT Engine
    _segmentSubscription?.cancel();
    _segmentSubscription = _vadService.speechSegmentStream.listen(
      _onSpeechSegmentDetected,
      onError: (Object error) {
        if (!_transcriptionController.isClosed) {
          _transcriptionController.addError(error);
        }
      },
    );

    await _audioService.start();
  }

  /// Internal handler for VAD speech segments
  Future<void> _onSpeechSegmentDetected(SpeechSegment segment) async {
    try {
      debugPrint('VAD detected speech segment: ${segment.samples.length} samples');
      final text = await _languageRouter.transcribeSegment(segment);
      debugPrint('Transcription result: "$text"');
      if (text.isNotEmpty && !_transcriptionController.isClosed) {
        _transcriptionController.add(text);
        debugPrint('Added transcription to stream: "$text"');
      } else {
        debugPrint('Empty transcription result, not adding to stream');
      }
    } catch (e) {
      debugPrint('SpeechToTextService transcription error: $e');
      if (!_transcriptionController.isClosed) {
        _transcriptionController.addError(e);
      }
    }
  }

  /// Stops microphone listening and flushes VAD buffers
  Future<void> stopListening() async {
    if (!isListening) return;

    await _segmentSubscription?.cancel();
    _segmentSubscription = null;

    _vadService.detachAudioStream();
    await _audioService.stop();
    _vadService.reset();
  }

  /// Cleanly disposes all resources and inner services
  Future<void> dispose() async {
    await stopListening();
    await _audioService.dispose();
    await _vadService.dispose();
    _languageRouter.dispose();
    await _transcriptionController.close();
    _isInitialized = false;
  }
}
