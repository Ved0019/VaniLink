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

class EditorialWalkieTalkieScreen extends StatefulWidget {
  const EditorialWalkieTalkieScreen({super.key});

  @override
  State<EditorialWalkieTalkieScreen> createState() =>
      _EditorialWalkieTalkieScreenState();
}

class _EditorialWalkieTalkieScreenState
    extends State<EditorialWalkieTalkieScreen> {
  // Services
  final SpeechToTextService _stt = SpeechToTextService();
  final P2PManager _p2p = P2PManager();
  final LatencyTracker _latency = LatencyTracker();

  // State
  String _liveTranscript = '';
  double _speechProb = 0.0;
  bool _isEmergencyMode = false;
  bool _showMap = false;
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showMap ? _buildMapView() : _buildDashboardView(),
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    return Padding(
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
          Text('Communicate\nand coordinate',
              style: GoogleFonts.manrope(
                  fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 24),

          // Transcript Card (Mint Green)
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
                    Text('Live Transcript',
                        style: GoogleFonts.manrope(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    Icon(
                        _stt.isListening ? Icons.mic : Icons.mic_none,
                        color: _stt.isListening ? Colors.red : Colors.black54),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _liveTranscript.isEmpty
                      ? 'Hold the PTT button to speak...'
                      : _liveTranscript,
                  style: GoogleFonts.manrope(
                      fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                // VAD Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LinearProgressIndicator(
                    value: _speechProb,
                    backgroundColor: Colors.white54,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.black),
                    minHeight: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Team / Peers Section
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
                    const Icon(Icons.hub_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('Your Network',
                        style: GoogleFonts.manrope(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Invite peers for offline comms',
                    style: GoogleFonts.manrope(
                        fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _showDiscoverySheet,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12, width: 2),
                        ),
                        child: const Icon(Icons.add),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_wifiP2PInfo?.isConnected == true)
                      const CircleAvatar(
                        radius: 25,
                        backgroundColor: Colors.black,
                        child: Icon(Icons.person, color: Colors.white),
                      )
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Map Preview Card (Black)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showMap = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.explore_outlined,
                                color: Colors.white),
                            const SizedBox(width: 8),
                            Text('View on the map',
                                style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: const Icon(Icons.share,
                              color: Colors.white, size: 16),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tracking Peers',
                                style: GoogleFonts.manrope(
                                    fontSize: 14, color: Colors.white54)),
                            Text('${_peerLocations.length} active',
                                style: GoogleFonts.manrope(
                                    fontSize: 16, color: Colors.white)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('View >',
                              style: GoogleFonts.manrope(color: Colors.white)),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    return Stack(
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
              GestureDetector(
                onTap: () => setState(() => _showMap = false),
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

                // PTT Button
                GestureDetector(
                  onTapDown: (_) {
                    _latency.onSpeechStarted();
                    _stt.startListening();
                  },
                  onTapUp: (_) => _stt.stopListening(),
                  onTapCancel: () => _stt.stopListening(),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isEmergencyMode ? Colors.red : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mic,
                      color: _isEmergencyMode ? Colors.white : Colors.black,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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