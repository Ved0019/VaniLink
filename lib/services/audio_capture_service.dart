import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Audio capture service responsible for streaming microphone audio,
/// converting to 16 kHz mono Float32 PCM, and emitting 30 ms (480 sample) chunks.
class AudioCaptureService {
  final AudioRecorder _audioRecorder;
  final StreamController<Float32List> _chunkController =
      StreamController<Float32List>.broadcast();

  StreamSubscription<Uint8List>? _streamSubscription;
  bool _isRecording = false;

  /// Target audio configuration
  static const int sampleRate = 16000;
  static const int chunkDurationMs = 30;
  static const int samplesPerChunk = (sampleRate * chunkDurationMs) ~/ 1000; // 480 samples

  // Efficient fixed-size buffer for chunking
  final Int16List _chunkBuffer = Int16List(samplesPerChunk);
  int _bufferCount = 0;

  AudioCaptureService({AudioRecorder? audioRecorder})
      : _audioRecorder = audioRecorder ?? AudioRecorder();

  /// Stream emitting continuous 30 ms (480 samples) Float32 normalized audio chunks
  Stream<Float32List> get audioChunkStream => _chunkController.stream;

  /// Active recording status
  bool get isRecording => _isRecording;

  /// Checks and requests microphone permission
  Future<bool> checkPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Starts real-time 16 kHz mono microphone capture
  Future<void> start() async {
    if (_isRecording) return;

    final hasPermission = await checkPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission is required for audio capture.');
    }

    _bufferCount = 0;

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    );

    try {
      final stream = await _audioRecorder.startStream(config);
      _isRecording = true;

      _streamSubscription = stream.listen(
        processRawBytes,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('AudioCaptureService error: $error');
          if (!_chunkController.isClosed) {
            _chunkController.addError(error, stackTrace);
          }
        },
        onDone: () {
          _flushBuffer();
        },
      );
    } catch (e) {
      _isRecording = false;
      rethrow;
    }
  }

  /// Processes raw 16-bit PCM byte stream into exact 480-sample Float32 chunks
  @visibleForTesting
  void processRawBytes(Uint8List rawBytes) {
    if (rawBytes.isEmpty) return;

    // View raw bytes as 16-bit signed integers (little-endian PCM)
    final int16Samples = Int16List.view(
      rawBytes.buffer,
      rawBytes.offsetInBytes,
      rawBytes.lengthInBytes ~/ 2,
    );

    int inputIndex = 0;
    while (inputIndex < int16Samples.length) {
      final needed = samplesPerChunk - _bufferCount;
      final available = int16Samples.length - inputIndex;
      final copyLength = available < needed ? available : needed;

      _chunkBuffer.setRange(
        _bufferCount,
        _bufferCount + copyLength,
        int16Samples,
        inputIndex,
      );

      _bufferCount += copyLength;
      inputIndex += copyLength;

      if (_bufferCount == samplesPerChunk) {
        _emitChunk(_chunkBuffer, samplesPerChunk);
        _bufferCount = 0;
      }
    }
  }

  /// Converts Int16 PCM samples to normalized Float32 values [-1.0, 1.0] and emits chunk
  void _emitChunk(Int16List samples, int length) {
    final floatSamples = Float32List(length);
    for (int i = 0; i < length; i++) {
      floatSamples[i] = samples[i] / 32768.0;
    }
    if (!_chunkController.isClosed) {
      _chunkController.add(floatSamples);
    }
  }

  /// Emits any remaining samples in buffer when stream ends
  void _flushBuffer() {
    if (_bufferCount > 0) {
      _emitChunk(_chunkBuffer, _bufferCount);
      _bufferCount = 0;
    }
  }

  /// Calculates Root Mean Square (RMS) volume of a Float32 chunk for UI meter visualization
  static double calculateRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    double sumSquares = 0.0;
    for (int i = 0; i < samples.length; i++) {
      sumSquares += samples[i] * samples[i];
    }
    return sqrt(sumSquares / samples.length);
  }

  /// Stops microphone streaming
  Future<void> stop() async {
    if (!_isRecording) return;

    await _streamSubscription?.cancel();
    _streamSubscription = null;
    try {
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint('Error stopping audio recorder: $e');
    }
    _flushBuffer();
    _isRecording = false;
  }

  /// Cleanly disposes service resources
  Future<void> dispose() async {
    await stop();
    await _audioRecorder.dispose();
    await _chunkController.close();
  }
}
