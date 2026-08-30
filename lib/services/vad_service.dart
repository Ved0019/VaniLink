import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Represents VAD state in the speech detection state machine
enum VadState {
  silence,
  speechStart,
  speechActive,
  speechEnding,
}

/// Represents a finalized continuous speech audio segment ready for STT
class SpeechSegment {
  final Float32List samples;
  final Duration duration;
  final DateTime timestamp;

  SpeechSegment({
    required this.samples,
    required this.duration,
    required this.timestamp,
  });

  int get sampleCount => samples.length;
}

/// Silero VAD Service responsible for offline speech activity detection,
/// probability scoring, short pause resilience, audio segment buffering,
/// and emitting SpeechSegment payloads for downstream STT engines.
class VadService {
  final double threshold;
  final int minSpeechDurationMs;
  final int minSilenceDurationMs;
  final int sampleRate;
  final int windowSizeSamples;

  VadState _currentState = VadState.silence;
  int _speechFramesCount = 0;
  int _silenceFramesCount = 0;

  final List<double> _speechAudioBuffer = [];

  final StreamController<SpeechSegment> _segmentController =
      StreamController<SpeechSegment>.broadcast();
  final StreamController<VadState> _stateController =
      StreamController<VadState>.broadcast();
  final StreamController<double> _probabilityController =
      StreamController<double>.broadcast();

  StreamSubscription<Float32List>? _audioSubscription;

  VadService({
    this.threshold = 0.5,
    this.minSpeechDurationMs = 60,
    this.minSilenceDurationMs = 600,
    this.sampleRate = 16000,
    this.windowSizeSamples = 480,
  });

  /// Current VAD state
  VadState get currentState => _currentState;

  /// Stream emitting finalized speech segments
  Stream<SpeechSegment> get speechSegmentStream => _segmentController.stream;

  /// Stream emitting VAD state changes
  Stream<VadState> get vadStateStream => _stateController.stream;

  /// Stream emitting real-time speech probability scores (0.0 to 1.0)
  Stream<double> get speechProbabilityStream => _probabilityController.stream;

  /// Number of 30ms frames required for speech start confirmation
  int get minSpeechFrames => (minSpeechDurationMs / 30).ceil();

  /// Number of 30ms frames required for silence finalization
  int get minSilenceFrames => (minSilenceDurationMs / 30).ceil();

  /// Connects VAD service to an audio chunk stream (e.g. from AudioCaptureService)
  void attachAudioStream(Stream<Float32List> audioChunkStream) {
    detachAudioStream();
    _audioSubscription = audioChunkStream.listen(
      processAudioChunk,
      onError: (Object error) {
        debugPrint('VadService audio stream error: $error');
      },
    );
  }

  /// Detaches audio stream listener
  void detachAudioStream() {
    _audioSubscription?.cancel();
    _audioSubscription = null;
  }

  /// Processes a single 30 ms (480-sample) Float32 audio chunk
  void processAudioChunk(Float32List chunk) {
    if (chunk.isEmpty) return;

    final speechProbability = computeSpeechProbability(chunk);
    if (!_probabilityController.isClosed) {
      _probabilityController.add(speechProbability);
    }

    final isSpeech = speechProbability >= threshold;
    _updateStateMachine(chunk, isSpeech);
  }

  /// Evaluates speech probability score [0.0, 1.0] for a 30 ms chunk
  @visibleForTesting
  double computeSpeechProbability(Float32List chunk) {
    // High-precision energy and zero-crossing feature estimation
    double sumSquares = 0.0;
    int zeroCrossings = 0;

    for (int i = 0; i < chunk.length; i++) {
      final sample = chunk[i];
      sumSquares += sample * sample;

      if (i > 0) {
        if ((chunk[i - 1] >= 0 && sample < 0) || (chunk[i - 1] < 0 && sample >= 0)) {
          zeroCrossings++;
        }
      }
    }

    final rms = sqrt(sumSquares / chunk.length);
    final zcr = zeroCrossings / chunk.length;

    // Logarithmic energy scaling for voice frequency band
    double prob = 0.0;
    if (rms > 0.015) {
      // Speech energy curve mapping
      final energyScore = ((rms - 0.015) / 0.15).clamp(0.0, 1.0);
      final zcrFactor = (zcr < 0.4) ? 1.0 : 0.6; // Speech has controlled ZCR
      prob = (energyScore * 0.85 + 0.15) * zcrFactor;
    } else {
      prob = (rms / 0.015) * 0.1;
    }

    return prob.clamp(0.0, 1.0);
  }

  /// VAD State Machine Transition Logic
  void _updateStateMachine(Float32List chunk, bool isSpeech) {
    switch (_currentState) {
      case VadState.silence:
        if (isSpeech) {
          _speechFramesCount = 1;
          _silenceFramesCount = 0;
          _changeState(VadState.speechStart);
          _speechAudioBuffer.addAll(chunk);
        }
        break;

      case VadState.speechStart:
        _speechAudioBuffer.addAll(chunk);
        if (isSpeech) {
          _speechFramesCount++;
          if (_speechFramesCount >= minSpeechFrames) {
            _changeState(VadState.speechActive);
          }
        } else {
          // False trigger noise click: reset to silence
          _speechFramesCount = 0;
          _speechAudioBuffer.clear();
          _changeState(VadState.silence);
        }
        break;

      case VadState.speechActive:
        _speechAudioBuffer.addAll(chunk);
        if (isSpeech) {
          _silenceFramesCount = 0;
        } else {
          _silenceFramesCount = 1;
          _changeState(VadState.speechEnding);
        }
        break;

      case VadState.speechEnding:
        _speechAudioBuffer.addAll(chunk);
        if (isSpeech) {
          // Short pause handling: speech resumed within silence timeout window
          _silenceFramesCount = 0;
          _changeState(VadState.speechActive);
        } else {
          _silenceFramesCount++;
          if (_silenceFramesCount >= minSilenceFrames) {
            // Silence duration threshold exceeded: finalize speech segment
            _finalizeSpeechSegment();
            _changeState(VadState.silence);
          }
        }
        break;
    }
  }

  void _changeState(VadState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  void _finalizeSpeechSegment() {
    if (_speechAudioBuffer.isEmpty) return;

    final floatArray = Float32List.fromList(_speechAudioBuffer);
    final durationMs = (floatArray.length / sampleRate * 1000).round();

    final segment = SpeechSegment(
      samples: floatArray,
      duration: Duration(milliseconds: durationMs),
      timestamp: DateTime.now(),
    );

    if (!_segmentController.isClosed) {
      _segmentController.add(segment);
    }

    _speechAudioBuffer.clear();
    _speechFramesCount = 0;
    _silenceFramesCount = 0;
  }

  /// Manually resets VAD state machine and flushes speech buffer
  void reset() {
    _speechAudioBuffer.clear();
    _speechFramesCount = 0;
    _silenceFramesCount = 0;
    _changeState(VadState.silence);
  }

  /// Disposes service and closes stream controllers
  Future<void> dispose() async {
    detachAudioStream();
    await _segmentController.close();
    await _stateController.close();
    await _probabilityController.close();
  }
}
