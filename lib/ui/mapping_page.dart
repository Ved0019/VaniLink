import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:vanilink/audio/emergency_volume.dart';
import 'package:vanilink/audio/tts_player.dart';
import 'package:vanilink/models/latency_tracker.dart';
import 'package:vanilink/networking/p2p_manager.dart';
import 'package:vanilink/services/language_router.dart';
import 'package:vanilink/services/speech_to_text_service.dart';
import 'package:vanilink/speech_service.dart';

class PeerLocation {
  final String ip;
  final LatLng position;
  final String lastMessage;
  final DateTime timestamp;

  PeerLocation(this.ip, this.position, this.lastMessage, this.timestamp);
}

class MappingPage extends StatefulWidget {
  const MappingPage({super.key});

  @override
  State<MappingPage> createState() => _MappingPageState();
}

class _MappingPageState extends State<MappingPage> {
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

  // Location State
  Position? _currentPosition;
  final Map<String, PeerLocation> _peerLocations = {};
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initServices();
    _initLocation();
  }

  Future<void> _initServices() async {
    await _stt.init();
    await _p2p.initialize();

    // Listen to STT live partials
    _stt.transcriptionStream.listen((text) {
      setState(() => _liveTranscript = text);
      if (text.isNotEmpty) {
        _p2p.sendTranscript(
          text,
          lat: _currentPosition?.latitude,
          lng: _currentPosition?.longitude,
        );
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

    // Handle incoming P2P messages and locations
    _p2p.onMessageReceived = (text, lat, lng) async {
      _latency.onP2pReceived();

      // Update peer location if provided
      if (lat != null && lng != null) {
        const ip = 'Peer'; // In a real app, map this to actual peer IP
        setState(() {
          _peerLocations[ip] = PeerLocation(
            ip,
            LatLng(lat, lng),
            text,
            DateTime.now(),
          );
        });
      }

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

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _currentPosition = await Geolocator.getCurrentPosition();
    if (mounted) setState(() {});

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (mounted) setState(() => _currentPosition = position);
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
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
        child: Stack(
          children: [
            // The Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition != null
                    ? LatLng(
                        _currentPosition!.latitude, _currentPosition!.longitude)
                    : const LatLng(20.5937, 78.9629), // Default India
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vanilink',
                ),
                MarkerLayer(
                  markers: [
                    // Current User
                    if (_currentPosition != null)
                      Marker(
                        point: LatLng(_currentPosition!.latitude,
                            _currentPosition!.longitude),
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    // Peers
                    ..._peerLocations.values.map((p) => Marker(
                          point: p.position,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(Icons.headset,
                                color: Colors.white, size: 20),
                          ),
                        )),
                  ],
                ),
              ],
            ),

            // Top Overlay
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black),
                    ),
                  ),
                  // Latency pills
                  StreamBuilder<LatencyReport>(
                    stream: _latency.reportStream,
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox();
                      return Row(
                        children: [
                          _buildStatPill(
                              Icons.speed, '${snap.data!.sttLatencyMs}ms',
                              color: const Color(0xFFBBE5D9)),
                          const SizedBox(width: 8),
                          _buildStatPill(
                              Icons.waves, snap.data!.rtf?.toStringAsFixed(2) ?? 'N/A',
                              color: const Color(0xFFBBE5D9)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom Controls (Pill shape)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Emergency Toggle
                    IconButton(
                      icon: Icon(
                        _isEmergencyMode ? Icons.warning : Icons.health_and_safety,
                        color: _isEmergencyMode ? Colors.red : Colors.white54,
                      ),
                      onPressed: _toggleEmergencyMode,
                    ),

                    // Language Selector
                    DropdownButtonHideUnderline(
                      child: DropdownButton<AppLanguage>(
                        dropdownColor: Colors.black87,
                        value: _selectedLanguage,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        style: GoogleFonts.manrope(color: Colors.white),
                        onChanged: (AppLanguage? newValue) {
                          if (newValue != null) {
                            setState(() => _selectedLanguage = newValue);
                            _stt.setLanguage(newValue);
                            SpeechService().setTtsLanguage(newValue.code);
                          }
                        },
                        items: AppLanguage.values.map((AppLanguage lang) {
                          return DropdownMenuItem<AppLanguage>(
                            value: lang,
                            child: Text(lang.displayName),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

  Widget _buildStatPill(IconData icon, String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.black87),
          const SizedBox(width: 4),
          Text(text,
              style: GoogleFonts.manrope(
                  fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}