import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vanilink/audio/emergency_volume.dart';
import 'package:vanilink/audio/tts_player.dart';
import 'package:vanilink/models/latency_tracker.dart';
import 'package:vanilink/networking/p2p_manager.dart';
import 'package:vanilink/services/language_router.dart';
import 'package:vanilink/services/speech_to_text_service.dart';
import 'package:vanilink/speech_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for messages shown in the chat ledger
// ─────────────────────────────────────────────────────────────────────────────
class _ChatMessage {
  final String text;
  final bool isMine;
  final DateTime timestamp;
  _ChatMessage({required this.text, required this.isMine})
      : timestamp = DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────
class EditorialWalkieTalkieScreen extends StatefulWidget {
  const EditorialWalkieTalkieScreen({super.key});

  @override
  State<EditorialWalkieTalkieScreen> createState() =>
      _EditorialWalkieTalkieScreenState();
}

class _EditorialWalkieTalkieScreenState
    extends State<EditorialWalkieTalkieScreen> {
  // ── Services ────────────────────────────────────────────────────────────────
  final _stt = SpeechToTextService();
  final _p2p = P2PManager();
  final _ttsPlayer = TtsPlayer();
  final _latency = LatencyTracker();

  // ── State ───────────────────────────────────────────────────────────────────
  bool _isRecording = false;
  bool _isConnected = false;
  bool _isEmergencyMode = false;
  bool _isInitializing = true;
  String _initError = '';

  AppLanguage _selectedLanguage = AppLanguage.hindi;
  double _speechProbability = 0.0;
  String _liveTranscript = 'Hold the transmit button to speak';
  LatencyReport? _lastLatency;

  final List<_ChatMessage> _messages = [];
  final List<DiscoveredPeers> _discoveredPeers = [];

  // ── Subscriptions ────────────────────────────────────────────────────────────
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<double>? _probabilitySub;
  StreamSubscription<LatencyReport>? _latencySub;

  // ── Design tokens ────────────────────────────────────────────────────────────
  static const _bgLight = Color(0xFFF4F5F7);
  static const _cardDark = Color(0xFF0F291E);
  static const _accentOrange = Color(0xFFD95338);
  static const _textMain = Color(0xFF111827);

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 1. Initialize STT pipeline
    try {
      await _stt.init();
      _stt.setLanguage(_selectedLanguage);
    } catch (e) {
      setState(() => _initError = 'STT init: $e');
    }

    // 2. Initialize sherpa-onnx TTS bindings
    try {
      await SpeechService().initModels();
    } catch (e) {
      // TTS is optional — app still useful without it
      debugPrint('TTS init note: $e');
    }

    // 3. Initialize P2P and hook up the receive callback
    await _p2p.initialize();
    _p2p.onMessageReceived = _onIncomingTranscript;

    // 4. Watch P2P connection state
    _p2p.streamWifiP2PInfo().listen((info) {
      if (mounted) setState(() => _isConnected = info.isConnected);
    });

    // 5. Subscribe to STT transcript stream
    _transcriptSub = _stt.transcriptionStream.listen((text) async {
      if (text.isEmpty) return;
      _latency.onSttCompleted();
      setState(() {
        _liveTranscript = text;
        _messages.add(_ChatMessage(text: text, isMine: true));
      });
      // Send over P2P
      await _p2p.sendTranscript(text);
      _latency.onP2pSent();
    });

    // 6. Subscribe to VAD probability for the waveform visualizer
    _probabilitySub = _stt.speechProbabilityStream.listen((p) {
      if (mounted) setState(() => _speechProbability = p);
    });

    // 7. Subscribe to latency reports for the debug overlay
    _latencySub = _latency.reportStream.listen((r) {
      if (mounted) setState(() => _lastLatency = r);
    });

    if (mounted) setState(() => _isInitializing = false);
  }

  // ── PTT handlers ─────────────────────────────────────────────────────────
  void _onPttDown() {
    if (_isInitializing) return;
    setState(() {
      _isRecording = true;
      _liveTranscript = 'Listening…';
    });
    _latency.onSpeechStarted();
    _stt.startListening();
  }

  void _onPttUp() {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    _stt.stopListening();
  }

  // ── Incoming P2P message → TTS ────────────────────────────────────────────
  Future<void> _onIncomingTranscript(String text) async {
    _latency.onP2pReceived();
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(text: text, isMine: false)));

    try {
      final samples = SpeechService().synthesizeSpeech(text);
      _latency.onTtsPlayed();
      if (_isEmergencyMode) {
        await _ttsPlayer.playAlert(samples);
      } else {
        await _ttsPlayer.playSpeech(samples);
      }
    } catch (e) {
      debugPrint('TTS playback error: $e');
    }
  }

  // ── Language change ───────────────────────────────────────────────────────
  void _onLanguageChanged(AppLanguage? lang) {
    if (lang == null) return;
    setState(() => _selectedLanguage = lang);
    _stt.setLanguage(lang);
  }

  // ── Emergency toggle ──────────────────────────────────────────────────────
  Future<void> _toggleEmergency() async {
    final next = !_isEmergencyMode;
    if (next) {
      await EmergencyVolume.activate();
    } else {
      await EmergencyVolume.deactivate();
    }
    setState(() => _isEmergencyMode = next);
  }

  // ── Peer discovery bottom-sheet ───────────────────────────────────────────
  Future<void> _showPeerDiscovery() async {
    setState(() => _discoveredPeers.clear());
    await _p2p.discoverPeers();

    // Listen for discovered peers and populate the list
    _p2p.streamPeers().take(1).listen((peers) {
      if (mounted) {
        setState(() {
          _discoveredPeers.clear();
          _discoveredPeers.addAll(peers);
        });
      }
    });

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PeerDiscoverySheet(
        peers: _discoveredPeers,
        onConnect: (address) async {
          Navigator.pop(context);
          await _p2p.connectToDevice(address);
        },
      ),
    );
  }

  @override
  void dispose() {
    _transcriptSub?.cancel();
    _probabilitySub?.cancel();
    _latencySub?.cancel();
    _stt.dispose();
    _p2p.dispose();
    _ttsPlayer.dispose();
    _latency.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildHeroCard(),
              const SizedBox(height: 12),
              _buildMetricsRow(),
              const SizedBox(height: 12),
              Expanded(child: _buildMessageLedger()),
              _buildVadBar(),
              const SizedBox(height: 16),
              _buildPttButton(),
              const SizedBox(height: 8),
              _buildBottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VaniLink P2P',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'Secure Transceiver',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _textMain,
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Emergency mode toggle
            GestureDetector(
              onTap: _toggleEmergency,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isEmergencyMode ? _accentOrange : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                    )
                  ],
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: _isEmergencyMode ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // P2P connect button
            GestureDetector(
              onTap: _showPeerDiscovery,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                    )
                  ],
                ),
                child: Icon(
                  _isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: _isConnected ? _cardDark : _accentOrange,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Hero live-transcript card ─────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Language selector
              DropdownButton<AppLanguage>(
                value: _selectedLanguage,
                dropdownColor: _cardDark,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                underline: const SizedBox(),
                items: AppLanguage.values.map((lang) {
                  return DropdownMenuItem(
                    value: lang,
                    child: Text(lang.displayName),
                  );
                }).toList(),
                onChanged: _onLanguageChanged,
              ),
              Icon(
                _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _isRecording ? _accentOrange : Colors.white60,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isInitializing ? 'Initializing models…' : _liveTranscript,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          if (_initError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '⚠️ $_initError',
              style: const TextStyle(color: _accentOrange, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _accentOrange, size: 14),
              const SizedBox(width: 4),
              Text(
                _isRecording ? 'Capturing voice…' : 'Ready to transmit',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Metrics row ────────────────────────────────────────────────────────────
  Widget _buildMetricsRow() {
    final sttMs = _lastLatency?.sttLatencyMs;
    final rtf = _lastLatency?.rtf;
    return Row(
      children: [
        Expanded(child: _metricCard(
          label: 'STT Latency',
          value: sttMs != null ? '${sttMs}ms' : '—',
          dark: false,
        )),
        const SizedBox(width: 12),
        Expanded(child: _metricCard(
          label: 'RTF',
          value: rtf != null ? rtf.toStringAsFixed(2) : '—',
          dark: true,
        )),
      ],
    );
  }

  Widget _metricCard({required String label, required String value, required bool dark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: dark ? _accentOrange : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: dark ? Colors.white70 : Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: dark ? Colors.white : _textMain,
          )),
        ],
      ),
    );
  }

  // ── Message ledger ────────────────────────────────────────────────────────
  Widget _buildMessageLedger() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Messages will appear here',
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[_messages.length - 1 - i];
        return Align(
          alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: msg.isMine ? _cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                color: msg.isMine ? Colors.white : _textMain,
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── VAD probability bar ───────────────────────────────────────────────────
  Widget _buildVadBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: _speechProbability,
        minHeight: 4,
        backgroundColor: Colors.grey[200],
        color: _isRecording ? _accentOrange : _cardDark,
      ),
    );
  }

  // ── PTT button ────────────────────────────────────────────────────────────
  Widget _buildPttButton() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTapDown: (_) => _onPttDown(),
            onTapUp: (_) => _onPttUp(),
            onPanEnd: (_) => _onPttUp(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _isRecording ? 92 : 104,
              height: _isRecording ? 92 : 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isEmergencyMode
                    ? (_isRecording ? Colors.red[700] : _accentOrange)
                    : (_isRecording ? _accentOrange : _cardDark),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? _accentOrange : _cardDark)
                        .withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  _isEmergencyMode ? Icons.campaign_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isEmergencyMode ? 'HOLD — EMERGENCY BROADCAST' : 'HOLD TO TRANSMIT',
            style: TextStyle(
              color: _isEmergencyMode ? _accentOrange : Colors.grey[500],
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, color: Colors.white70),
            onPressed: () {},
            tooltip: 'History',
          ),
          IconButton(
            icon: const Icon(Icons.forum_rounded, color: Colors.white),
            onPressed: () {},
            tooltip: 'Messages',
          ),
          IconButton(
            icon: Icon(
              Icons.settings_rounded,
              color: _isEmergencyMode ? _accentOrange : Colors.white70,
            ),
            onPressed: _toggleEmergency,
            tooltip: 'Emergency Mode',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Peer discovery bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _PeerDiscoverySheet extends StatelessWidget {
  final List<DiscoveredPeers> peers;
  final void Function(String address) onConnect;

  const _PeerDiscoverySheet({
    required this.peers,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nearby VaniLink Devices',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (peers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Scanning… ensure the other device has Wi-Fi Direct enabled.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...peers.map((peer) => ListTile(
                  leading: const Icon(Icons.smartphone_rounded, color: Colors.white70),
                  title: Text(
                    peer.deviceName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    peer.deviceAddress,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: TextButton(
                    onPressed: () => onConnect(peer.deviceAddress),
                    child: const Text('Connect', style: TextStyle(color: Color(0xFFD95338))),
                  ),
                )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}