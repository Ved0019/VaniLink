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

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  // Services
  final SpeechToTextService _stt = SpeechToTextService();
  final P2PManager _p2p = P2PManager();
  final LatencyTracker _latency = LatencyTracker();

  // Navigation
  final PageController _pageController = PageController(initialPage: 0);
  int _currentIndex = 0;

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
      if (mounted) setState(() => _liveTranscript = text);
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
      if (mounted) setState(() => _speechProb = prob);
    });

    // Listen to P2P network changes
    _p2p.streamWifiP2PInfo().listen((info) {
      if (mounted) {
        setState(() {
          _wifiP2PInfo = info;
          if (info.isConnected) {
            _connectionStatus =
                info.isGroupOwner ? 'Hosting Group' : 'Connected to Host';
          } else {
            _connectionStatus = 'Disconnected';
          }
        });
      }
    });

    _p2p.streamPeers().listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });

    // Handle incoming P2P messages and locations
    _p2p.onMessageReceived = (text, lat, lng) async {
      _latency.onP2pReceived();

      // Update peer location if provided
      if (lat != null && lng != null) {
        const ip = 'Peer'; // In a real app, map this to actual peer IP
        if (mounted) {
          setState(() {
            _peerLocations[ip] = PeerLocation(
              ip,
              LatLng(lat, lng),
              text,
              DateTime.now(),
            );
          });
        }
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
    _pageController.dispose();
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

  void _onNavTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      // Top Hamburger Menu Overlay
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getTitle(),
                  style: GoogleFonts.manrope(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Hamburger Menu matched to CO2 Calculator Reference
                Row(
                  children: [
                    Text(
                      'menu',
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.menu, size: 28),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fluid swiping between pages
          PageView(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildCommsPage(),
              _buildMapPage(),
              _buildNetworkPage(),
            ],
          ),
          
          // Floating Pill Navigation (Matched to Runmate reference)
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: _buildFloatingNavBar(),
          ),
        ],
      ),
      // Microphone Button (Floats above everything, offset slightly above pill)
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90.0),
        child: GestureDetector(
          onTapDown: (_) {
            _latency.onSpeechStarted();
            _stt.startListening();
          },
          onTapUp: (_) => _stt.stopListening(),
          onTapCancel: () => _stt.stopListening(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _stt.isListening ? 64.0 : 56.0,
            height: _stt.isListening ? 64.0 : 56.0,
            decoration: BoxDecoration(
              color: _isEmergencyMode ? Colors.red : Colors.black,
              shape: BoxShape.circle,
              boxShadow: [
                if (_stt.isListening)
                  BoxShadow(
                    color: _isEmergencyMode ? Colors.red.withOpacity(0.5) : Colors.black38,
                    blurRadius: 20,
                    spreadRadius: 4,
                  )
              ],
            ),
            child: Icon(
              _stt.isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  String _getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Communication';
      case 1:
        return 'Map Tracking';
      case 2:
        return 'Network Setup';
      default:
        return '';
    }
  }

  Widget _buildFloatingNavBar() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // Thick black pill
        borderRadius: BorderRadius.circular(36),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavItem(0, Icons.chat_bubble_outline, Icons.chat_bubble),
          _buildNavItem(1, Icons.map_outlined, Icons.map),
          _buildNavItem(2, Icons.hub_outlined, Icons.hub),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData iconOutlined, IconData iconFilled) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onNavTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withAlpha(50) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSelected ? iconFilled : iconOutlined,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  // ─── PAGES ────────────────────────────────────────────────────────────────

  Widget _buildCommsPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
                    minHeight: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Status & Emergency Settings
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
                    const Icon(Icons.settings, size: 20),
                    const SizedBox(width: 8),
                    Text('Settings',
                        style: GoogleFonts.manrope(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Emergency Toggle inside card
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Emergency Mode',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600)),
                    Switch(
                      value: _isEmergencyMode,
                      activeColor: Colors.red,
                      onChanged: (val) => _toggleEmergencyMode(),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Language Selector inside card
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Language',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600)),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<AppLanguage>(
                        value: _selectedLanguage,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                        style: GoogleFonts.manrope(color: Colors.black, fontWeight: FontWeight.bold),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPage() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
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
                  point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 20),
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
                      child: const Icon(Icons.headset, color: Colors.white, size: 20),
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Build your\nmesh network',
              style: GoogleFonts.manrope(
                  fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 24),
          
          // Connection Status Card
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Status',
                        style: GoogleFonts.manrope(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _wifiP2PInfo?.isConnected == true
                            ? Colors.green.withAlpha(50)
                            : Colors.grey.withAlpha(50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _connectionStatus,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _wifiP2PInfo?.isConnected == true
                              ? Colors.green[700]
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Add Peer Button
                InkWell(
                  onTap: _showDiscoverySheet,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add),
                        const SizedBox(width: 8),
                        Text('Discover Peers',
                            style: GoogleFonts.manrope(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Latency Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A), // Thick black card
              borderRadius: BorderRadius.circular(32),
            ),
            child: StreamBuilder<LatencyReport>(
              stream: _latency.reportStream,
              builder: (context, snap) {
                final sttMs = snap.data?.sttLatencyMs ?? 0;
                final rtf = snap.data?.rtf?.toStringAsFixed(2) ?? 'N/A';
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text('Performance Metrics',
                            style: GoogleFonts.manrope(
                                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetricColumn('STT Latency', '${sttMs}ms'),
                        _buildMetricColumn('RTF', rtf),
                        _buildMetricColumn('Peers', '${_peers.length}'),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.manrope(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}
