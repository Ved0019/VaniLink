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

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  // Services
  final SpeechToTextService _stt = SpeechToTextService();
  final P2PManager _p2p = P2PManager();
  final LatencyTracker _latency = LatencyTracker();

  // State
  String _liveTranscript = '';
  double _speechProb = 0.0;
  bool _isEmergencyMode = false;
  AppLanguage _selectedLanguage = AppLanguage.english;

  // Connection State
  String _connectionStatus = 'Disconnected';
  List<DiscoveredPeers> _peers = [];
  WifiP2PInfo? _wifiP2PInfo;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _stt.init();
    await _p2p.initialize();

    // Listen to STT live partials
    _stt.transcriptionStream.listen((text) {
      setState(() => _liveTranscript = text);
      if (text.isNotEmpty) {
        // Note: Location not available in network page, but we keep the functionality
        _p2p.sendTranscript(text);
      }
    });

    // Listen to STT VAD probability for UI feedback
    _stt.speechProbabilityStream.listen((prob) {
      setState(() => _speechProb = prob);
    });

    // Listen to P2P network changes
    _p2p.streamWifiP2PInfo().listen((info) {
      setState(() {
        _wifiP2PInfo = info;
        if (info.isConnected) {
          _connectionStatus =
              info.isGroupOwner ? 'Hosting Group' : 'Connected to Host';
        } else {
          _connectionStatus = 'Disconnected';
        }
      });
    });

    _p2p.streamPeers().listen((peers) {
      setState(() => _peers = peers);
    });

    // Handle incoming P2P messages
    _p2p.onMessageReceived = (text, lat, lng) async {
      _latency.onP2pReceived();

      // Synthesize and play
      final audio = SpeechService().synthesizeSpeech(text);
      if (audio.isNotEmpty) {
        if (_isEmergencyMode) {
          await TtsPlayer().playAlert(audio);
        } else {
          await TtsPlayer().playSpeech(audio);
        }
        _latency.onTtsPlayed();
      }
    };
  }

  @override
  void dispose() {
    _stt.dispose();
    _p2p.dispose();
    super.dispose();
  }

  void _toggleEmergencyMode() {
    setState(() {
      _isEmergencyMode = !_isEmergencyMode;
    });
    if (_isEmergencyMode) {
      EmergencyVolume.activate();
    } else {
      EmergencyVolume.deactivate();
    }
  }

  void _showDiscoverySheet() {
    _p2p.discoverPeers();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Discovered Peers',
                style: GoogleFonts.manrope(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_peers.isEmpty) const Text('Searching for VaniLink devices...'),
            ..._peers.map((p) => ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: Colors.black,
                      child: Icon(Icons.wifi, color: Colors.white)),
                  title: Text(p.deviceName,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                  subtitle: Text(p.deviceAddress),
                  onTap: () {
                    _p2p.connectToDevice(p.deviceAddress);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12, width: 2),
                      ),
                      child: const Icon(Icons.menu, color: Colors.black),
                    ),
                    Column(
                      children: [
                        Text('VaniLink',
                            style: GoogleFonts.manrope(
                                fontSize: 14, color: Colors.black54)),
                        Text(_connectionStatus,
                            style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _wifiP2PInfo?.isConnected == true
                                    ? Colors.green
                                    : Colors.black)),
                      ],
                    ),
                    GestureDetector(
                      onTap: _showDiscoverySheet,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(Icons.share, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Manage your\nnetwork connections',
                    style: GoogleFonts.manrope(
                        fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
                const SizedBox(height: 24),

                // Network Status Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBBE5D9),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Network Status',
                              style: GoogleFonts.manrope(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          Icon(
                              Icons.wifi,
                              color: _wifiP2PInfo?.isConnected == true
                                  ? Colors.green
                                  : Colors.grey),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _connectionStatus,
                        style: GoogleFonts.manrope(
                            fontSize: 16, color: Colors.black87),
                      ),
                      const SizedBox(height: 16),
                      // Connection details
                      if (_wifiP2PInfo != null) ...[
                        Text('Group Owner: ${_wifiP2PInfo?.isGroupOwner == true ? 'Yes' : 'No'}',
                            style: GoogleFonts.manrope(fontSize: 14)),
                      ] else ...[
                        Text('Not connected to any network',
                            style: GoogleFonts.manrope(fontSize: 14, color: Colors.black54)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Discovered Peers Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.people_outline, size: 20),
                          const SizedBox(width: 8),
                          Text('Discovered Devices',
                              style: GoogleFonts.manrope(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Tap to connect to nearby VaniLink devices',
                          style: GoogleFonts.manrope(
                              fontSize: 14, color: Colors.black54)),
                      const SizedBox(height: 16),
                      if (_peers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No devices found',
                                  style: GoogleFonts.manrope(
                                      fontSize: 16, color: Colors.black54)),
                              const SizedBox(height: 8),
                              Text('Make sure devices are nearby and have VaniLink running',
                                  style: GoogleFonts.manrope(
                                      fontSize: 14, color: Colors.black54)),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _peers.length,
                          itemBuilder: (context, index) {
                            final peer = _peers[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                  backgroundColor: Colors.black,
                                  child: Icon(Icons.wifi, color: Colors.white)),
                              title: Text(peer.deviceName,
                                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                              subtitle: Text(peer.deviceAddress),
                              trailing: Icon(Icons.chevron_right, color: Colors.grey[600]),
                              onTap: () {
                                _p2p.connectToDevice(peer.deviceAddress);
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Connected Peers Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Connected Peers',
                              style: GoogleFonts.manrope(
                                  fontSize: 18, fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          Text('${_peers.length} discovered',
                              style: GoogleFonts.manrope(
                                  fontSize: 16, color: Colors.white70)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // For now, showing a placeholder since we don't have connected peers state
                      // In a real implementation, this would show actual connected peers
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.link, size: 48, color: Colors.white70),
                            const SizedBox(height: 16),
                            Text('Connected peers will appear here',
                                style: GoogleFonts.manrope(
                                    fontSize: 16, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: GestureDetector(
        onTapDown: (_) {
          _latency.onSpeechStarted();
          _stt.startListening();
        },
        onTapUp: (_) => _stt.stopListening(),
        onTapCancel: () => _stt.stopListening(),
        child: Container(
          width: 56.0,
          height: 56.0,
          decoration: BoxDecoration(
            color: _isEmergencyMode ? Colors.red : Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _stt.isListening ? Icons.mic : Icons.mic_none,
            color: _isEmergencyMode ? Colors.white : Colors.black,
            size: 28,
          ),
        ),
      ),
    );
  }
}