import 'dart:async';

/// Timestamps recorded at each stage of the STT → P2P → TTS pipeline.
class LatencyReport {
  final DateTime speechStarted;
  final DateTime? vadFired;
  final DateTime? sttCompleted;
  final DateTime? p2pSent;
  final DateTime? p2pReceived;
  final DateTime? ttsPlayed;
  final Duration audioDuration;

  LatencyReport({
    required this.speechStarted,
    this.vadFired,
    this.sttCompleted,
    this.p2pSent,
    this.p2pReceived,
    this.ttsPlayed,
    required this.audioDuration,
  });

  /// Time from speech start → STT completion (ms)
  int? get sttLatencyMs => sttCompleted != null
      ? sttCompleted!.difference(speechStarted).inMilliseconds
      : null;

  /// Time from P2P received → TTS audio started (ms)
  int? get ttsLatencyMs =>
      (p2pReceived != null && ttsPlayed != null)
          ? ttsPlayed!.difference(p2pReceived!).inMilliseconds
          : null;

  /// Full loop: speech started → audio played on other device (ms)
  int? get e2eLatencyMs =>
      (ttsPlayed != null)
          ? ttsPlayed!.difference(speechStarted).inMilliseconds
          : null;

  /// Real-Time Factor = processing_time / audio_duration (lower is better)
  double? get rtf {
    if (sttCompleted == null || audioDuration.inMilliseconds == 0) return null;
    final processingMs = sttCompleted!.difference(speechStarted).inMilliseconds;
    return processingMs / audioDuration.inMilliseconds;
  }

  @override
  String toString() {
    return 'LatencyReport { '
        'STT: ${sttLatencyMs}ms, '
        'TTS: ${ttsLatencyMs}ms, '
        'E2E: ${e2eLatencyMs}ms, '
        'RTF: ${rtf?.toStringAsFixed(2)} '
        '}';
  }
}

/// Singleton tracker that measures timing at each pipeline stage.
/// Subscribe to [reportStream] to receive completed latency reports.
class LatencyTracker {
  static final LatencyTracker _instance = LatencyTracker._internal();
  factory LatencyTracker() => _instance;
  LatencyTracker._internal();

  final StreamController<LatencyReport> _controller =
      StreamController<LatencyReport>.broadcast();

  Stream<LatencyReport> get reportStream => _controller.stream;

  // Mutable stage timestamps for the current utterance
  DateTime? _speechStarted;
  DateTime? _vadFired;
  DateTime? _sttCompleted;
  DateTime? _p2pSent;
  DateTime? _p2pReceived;
  Duration _audioDuration = Duration.zero;

  void onSpeechStarted() {
    _speechStarted = DateTime.now();
    _vadFired = null;
    _sttCompleted = null;
    _p2pSent = null;
    _p2pReceived = null;
    _ttsPlayed = null;
    _audioDuration = Duration.zero;
  }

  void onVadFired(Duration audioDuration) {
    _vadFired = DateTime.now();
    _audioDuration = audioDuration;
  }

  void onSttCompleted() => _sttCompleted = DateTime.now();
  void onP2pSent() => _p2pSent = DateTime.now();
  void onP2pReceived() {
    _p2pReceived = DateTime.now();
    _speechStarted ??= _p2pReceived; // receiver side: use receive time as start
  }

  DateTime? _ttsPlayed;

  void onTtsPlayed() {
    _ttsPlayed = DateTime.now();
    _emitReport();
  }

  void _emitReport() {
    if (_speechStarted == null) return;
    final report = LatencyReport(
      speechStarted: _speechStarted!,
      vadFired: _vadFired,
      sttCompleted: _sttCompleted,
      p2pSent: _p2pSent,
      p2pReceived: _p2pReceived,
      ttsPlayed: _ttsPlayed,
      audioDuration: _audioDuration,
    );
    if (!_controller.isClosed) _controller.add(report);
  }

  void dispose() {
    _controller.close();
  }
}

