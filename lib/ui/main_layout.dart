import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class ChatMessage {
  final String sender;
  final String text;
  final String lang;
  final dynamic bytes;
  final bool isIncoming;

  ChatMessage(this.sender, this.text, this.lang, this.bytes, this.isIncoming);
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // State
  String _liveTranscript = '';
  final List<ChatMessage> _messages = [];
  bool _isEmergencyMode = false;
  bool _isLoopbackTestEnabled = false;

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
    });

    // Listen to STT VAD probability for UI feedback
    _stt.speechProbabilityStream.listen((prob) {
      // Unused in current UI structure, but stream must be consumed
    });

    // Listen to P2P network changes
    _p2p.streamWifiP2PInfo().listen((info) {
      if (mounted) {
        setState(() {
          _wifiP2PInfo = info;
          if (info.isConnected) {
            _connectionStatus =
                info.isGroupOwner ? 'Group Owner' : 'Connected';
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
      
      const peerName = 'Peer'; 
      if (mounted) {
        setState(() {
          _messages.insert(
            0,
            ChatMessage(peerName, text, _selectedLanguage.code.toUpperCase(), utf8.encode(text).length, true),
          );
          if (lat != null && lng != null) {
            _peerLocations[peerName] = PeerLocation(
              peerName, LatLng(lat, lng), text, DateTime.now(),
            );
          }
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

    _positionStream = Geolocator.getPositionStream().listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
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

  void _onPttPress() {
    HapticFeedback.heavyImpact();
    setState(() {
      _liveTranscript = '';
    });
    _latency.onSpeechStarted();
    _stt.startListening();
  }

  void _onPttRelease() {
    HapticFeedback.mediumImpact();
    _stt.stopListening();
    if (_liveTranscript.trim().isNotEmpty) {
      final textToSend = _liveTranscript.trim();
      setState(() {
        _messages.insert(
          0,
          ChatMessage('You', textToSend, _selectedLanguage.code.toUpperCase(), utf8.encode(textToSend).length, false),
        );
        _liveTranscript = '';
      });
      _p2p.sendTranscript(
        textToSend,
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );

      // Local Loopback Test
      if (_isLoopbackTestEnabled) {
        final audio = SpeechService().synthesizeSpeech(textToSend);
        if (audio.isNotEmpty) {
          TtsPlayer().playSpeech(audio);
        }
      }
    }
  }

  void _toggleEmergencyMode() {
    setState(() => _isEmergencyMode = !_isEmergencyMode);
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
            Text(
              'Discovered Peers',
              style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_peers.isEmpty)
              const Text('Searching for VaniLink devices nearby...'),
            ..._peers.map(
              (p) => ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF14171E),
                  child: Icon(Icons.wifi, color: Colors.white),
                ),
                title: Text(p.deviceName, style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                subtitle: Text(p.deviceAddress),
                onTap: () {
                  _p2p.connectToDevice(p.deviceAddress);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI BUILD ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F6FB), // Vibrant Canvas
      drawer: _buildHamburgerDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentIndex = idx),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildCommsPage(),
                  _buildMapPage(),
                  _buildNetworkPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHamburgerDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF14171E),
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'VaniLink\nNavigation',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  color: const Color(0xFF14171E),
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
            _buildDrawerItem(Icons.chat_bubble_outline_rounded, 'Communication', 0),
            _buildDrawerItem(Icons.map_outlined, 'Map Tracking', 1),
            _buildDrawerItem(Icons.hub_outlined, 'Network & Mesh', 2),
            const Divider(color: Colors.white24, indent: 24, endIndent: 24, height: 40),
            const Divider(color: Colors.black12, indent: 24, endIndent: 24, height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text('Diagnostics (Local Loopback)', 
                style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                style: GoogleFonts.manrope(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text('Enable Mic Loopback', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('TTS plays your own STT output', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12)),
              title: Text('Enable Mic Loopback', style: GoogleFonts.manrope(color: const Color(0xFF14171E), fontWeight: FontWeight.bold)),
              subtitle: Text('TTS plays your own STT output', style: GoogleFonts.manrope(color: Colors.black54, fontSize: 12)),
              value: _isLoopbackTestEnabled,
              activeTrackColor: const Color(0xFFD4F651),
              activeTrackColor: const Color(0xFFFF6B4A),
              onChanged: (val) {
                setState(() => _isLoopbackTestEnabled = val);
              },
            ),
            ListTile(
              leading: const Icon(Icons.volume_up, color: Color(0xFF38B6FF)),
              title: Text('Test TTS Synthesis', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('Plays predefined test string', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12)),
              leading: const Icon(Icons.volume_up, color: Color(0xFFFF6B4A)),
              title: Text('Test TTS Synthesis', style: GoogleFonts.manrope(color: const Color(0xFF14171E), fontWeight: FontWeight.bold)),
              subtitle: Text('Plays predefined test string', style: GoogleFonts.manrope(color: Colors.black54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(context); // close drawer
                final testStr = _selectedLanguage.code == 'hi' 
                    ? "नमस्ते, वानीलिंक वॉकी-टॉकी का परीक्षण सफल रहा।"
                    : "VaniLink walkie talkie test. System is operational.";
                final audio = SpeechService().synthesizeSpeech(testStr);
                if (audio.isNotEmpty) {
                  await TtsPlayer().playSpeech(audio);
                }
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Status: $_connectionStatus',
                style: GoogleFonts.manrope(color: Colors.white54, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, int pageIndex) {
    final isSelected = _currentIndex == pageIndex;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFF38B6FF) : Colors.white70),
      leading: Icon(icon, color: isSelected ? const Color(0xFFFF6B4A) : Colors.black54),
      title: Text(
        title,
        style: GoogleFonts.manrope(
          color: isSelected ? Colors.white : Colors.white70,
          color: isSelected ? const Color(0xFFFF6B4A) : const Color(0xFF14171E),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 18,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        _pageController.animateToPage(
          pageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: Color(0xFF14171E), size: 28),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Text(
                'VaniLink',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: const Color(0xFF14171E),
                ),
              ),
              // Language Selector Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E6EF)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AppLanguage>(
                    value: _selectedLanguage,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF14171E)),
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF14171E),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    onChanged: (lang) {
                      if (lang != null) {
                        setState(() => _selectedLanguage = lang);
                        _stt.setLanguage(lang);
                      }
                    },
                    items: AppLanguage.values.map((lang) {
                      return DropdownMenuItem(
                        value: lang,
                        child: Text(lang.name),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Connection Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _wifiP2PInfo?.isConnected == true
                  ? const Color(0xFF34C759) // Green like reference
                  : Colors.amber,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _wifiP2PInfo?.isConnected == true ? Icons.wifi : Icons.sync,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _wifiP2PInfo?.isConnected == true ? 'Wi-Fi Direct Connected' : 'Syncing...',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TABS / PAGES ────────────────────────────────────────────────────────
  Widget _buildCommsPage() {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGiantPttButton(),
              const SizedBox(height: 24),
              Text(
                'Push-to-Talk',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF14171E),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC), // Very light grey blue
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E6EF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: _buildTranscriptList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGiantPttButton() {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.heavyImpact();
        _onPttPress();
      },
      onTapUp: (_) {
        _onPttRelease();
      },
      onTapCancel: () {
        _onPttRelease();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _stt.isListening ? 190 : 200,
        height: _stt.isListening ? 190 : 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF6B4A), // Electric Coral
          border: Border.all(
            color: const Color(0xFFD84A2A), // Darker Orange Border
            width: 14,
          ),
          boxShadow: [
            if (_stt.isListening)
              BoxShadow(
                color: const Color(0xFFFF6B4A).withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 10,
              )
            else
              BoxShadow(
                color: const Color(0xFFFF6B4A).withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: const Icon(
          Icons.graphic_eq_rounded,
          size: 64,
          color: Colors.white, // Waveform icon
        ),
      ),
    );
  }

  Widget _buildTranscriptList() {
    final totalCount = _messages.length + (_liveTranscript.isNotEmpty ? 1 : 0);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      physics: const BouncingScrollPhysics(),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (_liveTranscript.isNotEmpty && index == 0) {
          return _buildMessageBubble(
            sender: 'You (Speaking...)',
            text: _liveTranscript,
            lang: _selectedLanguage.name.toUpperCase(),
            bytes: utf8.encode(_liveTranscript).length,
            isIncoming: false,
          );
        }
        final msgIndex = _liveTranscript.isNotEmpty ? index - 1 : index;
        final msg = _messages[msgIndex];
        return _buildMessageBubble(
          sender: msg.sender,
          text: msg.text,
          lang: msg.lang,
          bytes: msg.bytes,
          isIncoming: msg.isIncoming,
        );
      },
    );
  }

  Widget _buildMessageBubble({
    required String sender,
    required String text,
    required String lang,
    required dynamic bytes,
    required bool isIncoming,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isIncoming ? Colors.white : const Color(0xFFE8FBD9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isIncoming ? const Color(0xFFE5E9F2) : const Color(0xFFC7F0A1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sender,
                style: GoogleFonts.manrope(
                  color: isIncoming ? const Color(0xFF4D8BFF) : const Color(0xFF14171E),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14171E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lang,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$bytes B',
                    style: GoogleFonts.manrope(
                      color: Colors.black45,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: GoogleFonts.manrope(
              color: const Color(0xFF14171E),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (isIncoming) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: Color(0xFF4D8BFF), size: 16),
                const SizedBox(width: 6),
                Text(
                  'Synthesized via on-device TTS',
                  style: GoogleFonts.manrope(
                    color: const Color(0xFF4D8BFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapPage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 120.0),
      padding: const EdgeInsets.only(bottom: 20.0),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : const LatLng(20.5937, 78.9629),
            initialZoom: 15.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.vanilink',
            ),
            MarkerLayer(
              markers: [
                if (_currentPosition != null)
                  Marker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF38B6FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                  ),
                ..._peerLocations.values.map(
                  (p) => Marker(
                    point: p.position,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF14171E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.headset, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Mesh Network',
                        style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _wifiP2PInfo?.isConnected == true
                            ? const Color(0xFFD4F651)
                            : const Color(0xFFE2E6EF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _connectionStatus,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF14171E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: _showDiscoverySheet,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF14171E), width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.radar, color: Color(0xFF14171E)),
                        const SizedBox(width: 8),
                        Text(
                          'Discover Peers',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF14171E),
                          ),
                        ),
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
              color: const Color(0xFF14171E),
              borderRadius: BorderRadius.circular(24),
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
                        Text(
                          'Telemetry',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetricColumn('STT Latency', '${sttMs}ms'),
                        _buildMetricColumn('RTF', rtf),
                        _buildMetricColumn('Active Nodes', '${_peers.length}'),
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
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            color: Colors.white54,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }


}
