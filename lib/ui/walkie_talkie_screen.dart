import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // Optional: Use Google Fonts for clean typography

class EditorialWalkieTalkieScreen extends StatefulWidget {
  const EditorialWalkieTalkieScreen({Key? key}) : super(key: key);

  @override
  State<EditorialWalkieTalkieScreen> createState() => _EditorialWalkieTalkieScreenState();
}

class _EditorialWalkieTalkieScreenState extends State<EditorialWalkieTalkieScreen> {
  bool _isRecording = false;
  bool _isConnected = true;
  String _liveTranscript = "Tap and hold the transmitter below to broadcast voice notes offline.";
  
  // Design color palette inspired by modern editorial apps
  static const Color bgLight = Color(0xFFF4F5F7);
  static const Color cardDark = Color(0xFF0F291E); // Deep Forest Green
  static const Color accentOrange = Color(0xFFD95338); // Terracotta Accent
  static const Color textMain = Color(0xFF111827);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Top Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "VaniLink P2P",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Secure Transceiver",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textMain,
                        ),
                      ),
                    ],
                  ),
                  // Status Avatar / Connection Badge
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: _isConnected ? cardDark : accentOrange,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- Hero Status Card (Dark Block) ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardDark,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "LIVE FREQUENCY",
                            style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1),
                          ),
                        ),
                        Icon(
                          _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isRecording ? accentOrange : Colors.white60,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _liveTranscript,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: accentOrange, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _isRecording ? "Transmitting audio stream..." : "Ready for broadcast",
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Grid Metrics / Quick Info Cards ---
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Latency", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          const SizedBox(height: 6),
                          const Text("< 45ms", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textMain)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: accentOrange,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Link Type", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          SizedBox(height: 6),
                          Text("P2P Wi-Fi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              const Spacer(),

              // --- Floating Push-To-Talk Button ---
              Center(
                child: GestureDetector(
                  onTapDown: (_) => setState(() {
                    _isRecording = true;
                    _liveTranscript = "Listening to voice input...";
                  }),
                  onTapUp: (_) => setState(() {
                    _isRecording = false;
                    _liveTranscript = "Sample translated text output successfully sent over local peer network.";
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isRecording ? 95 : 105,
                    height: _isRecording ? 95 : 105,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? accentOrange : cardDark,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? accentOrange : cardDark).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mic_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  "HOLD TO TRANSMIT",
                  style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),

              // --- Floating Bottom Capsule Navigation ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: cardDark,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.grid_view_rounded, color: Colors.white70),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.forum_rounded, color: Colors.white),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}