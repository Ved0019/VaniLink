import 'dart:convert';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class P2PManager {
  static final P2PManager _instance = P2PManager._internal();
  factory P2PManager() => _instance;
  P2PManager._internal();

  final FlutterP2pConnection _p2p = FlutterP2pConnection();
  bool _isInitialized = false;
  
  // Callback to handle incoming text payloads from the remote phone
  Function(String)? onMessageReceived;

  /// Initializes the Wi-Fi Direct framework and listeners
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _p2p.initialize();
    
    // Listen to Wi-Fi Direct connection changes to establish a socket
    _p2p.streamWifiP2PInfo().listen((info) async {
      if (info.isConnected && info.groupFormed) {
        // Delay slightly to ensure IP addresses are fully resolved by Android
        await Future.delayed(const Duration(seconds: 1));
        
        if (info.isGroupOwner) {
          await _p2p.startSocket(
            groupOwnerAddress: info.groupOwnerAddress,
            downloadPath: "/storage/emulated/0/Download/", // Required parameter, even if unused
            maxConcurrentDownloads: 1,
            deleteOnError: true,
            onConnect: (name, address) {
              print("Client connected to socket: $name $address");
            },
            transferUpdate: (transfer) {}, // Ignoring files for now
            receiveString: (req) {
              _handleReceivedString(req.toString());
            },
          );
        } else {
          await _p2p.connectToSocket(
            groupOwnerAddress: info.groupOwnerAddress,
            downloadPath: "/storage/emulated/0/Download/",
            maxConcurrentDownloads: 1,
            deleteOnError: true,
            onConnect: (address) {
              print("Connected to host socket: $address");
            },
            transferUpdate: (transfer) {}, // Ignoring files for now
            receiveString: (req) {
              _handleReceivedString(req.toString());
            },
          );
        }
      }
    });

    _isInitialized = true;
  }

  void _handleReceivedString(String req) {
    try {
      final jsonMap = jsonDecode(req);
      if (jsonMap['type'] == 'transcript' && onMessageReceived != null) {
        onMessageReceived!(jsonMap['payload']);
      }
    } catch (e) {
      print("Error decoding incoming P2P payload: $e");
    }
  }

  /// Discovers nearby devices running VaniLink
  Future<void> discoverPeers() async {
    await _p2p.discover();
  }

  /// Connects to a specific peer device address
  Future<bool> connectToDevice(String address) async {
    return await _p2p.connect(address);
  }

  /// Transmits the compressed text transcript over the low-bitrate P2P link
  Future<void> sendTranscript(String text) async {
    final payload = jsonEncode({
      'type': 'transcript',
      'payload': text,
    });
    
    _p2p.sendStringToSocket(payload);
  }

  void dispose() {
    _p2p.removeGroup();
    _p2p.stopDiscovery();
  }
}
