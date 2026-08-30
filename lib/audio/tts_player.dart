import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Singleton audio player that converts sherpa-onnx Float32List PCM samples
/// into a WAV byte buffer and plays them via audioplayers.
///
/// Supports two modes:
/// - [playSpeech] — normal TTS output at current system volume
/// - [playAlert]  — emergency mode: forces max alarm volume, non-interruptible
class TtsPlayer {
  static final TtsPlayer _instance = TtsPlayer._internal();
  factory TtsPlayer() => _instance;
  TtsPlayer._internal();

  static const _channel = MethodChannel('vanilink/audio');

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Plays TTS audio at normal volume. Safe to interrupt.
  Future<void> playSpeech(Float32List samples, {int sampleRate = 22050}) async {
    if (_isPlaying) await stop();
    final wav = _buildWav(samples, sampleRate);
    await _playWav(wav);
  }

  /// Plays a TTS alert at full volume using the Android STREAM_ALARM channel.
  /// Cannot be silenced by the user's volume buttons or Do Not Disturb.
  Future<void> playAlert(Float32List samples, {int sampleRate = 22050}) async {
    if (_isPlaying) await stop();
    try {
      await _channel.invokeMethod('setAlarmVolume');
    } catch (e) {
      debugPrint('TtsPlayer: setAlarmVolume failed (non-Android?): $e');
    }
    final wav = _buildWav(samples, sampleRate);
    await _playWav(wav);
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
  }

  Future<void> _playWav(Uint8List wavBytes) async {
    _isPlaying = true;
    _player.onPlayerComplete.first.then((_) => _isPlaying = false);
    await _player.play(BytesSource(wavBytes));
  }

  /// Builds a valid 16-bit PCM WAV container around a Float32 sample array.
  Uint8List _buildWav(Float32List samples, int sampleRate) {
    // Convert Float32 [-1.0, 1.0] → Int16 PCM
    final int16 = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      int16[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    }
    final pcmBytes = int16.buffer.asUint8List();

    final int numChannels = 1;
    final int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final int blockAlign = numChannels * bitsPerSample ~/ 8;
    final int dataSize = pcmBytes.length;
    final int chunkSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF chunk
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);  // 'W'
    header.setUint8(9, 0x41);  // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'
    // fmt sub-chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);          // Subchunk1Size
    header.setUint16(20, 1, Endian.little);           // AudioFormat: PCM
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data sub-chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + dataSize);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(44, pcmBytes);
    return result;
  }

  void dispose() {
    _player.dispose();
  }
}
