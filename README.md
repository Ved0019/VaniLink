# VaniLink 📱

**Offline P2P Walkie-Talkie with On-Device Indic Speech Recognition & Synthesis**

VaniLink is an Android Flutter application that enables secure, private voice communication over local Wi-Fi Direct peer-to-peer networks. It converts speech to text locally on your device using on-device neural models, sends compact text payloads, and synthesizes speech back on the receiving device—all without internet connectivity.

---

## 🎯 Product Vision

VaniLink is intended to become a fully **offline, local-first neural transceiver** for voice communication across **10+ target languages**: 
- 🇮🇳 Hindi, Gujarati, Marathi, Kannada, Malayalam, Tamil, Telugu, Odia, Bengali
- 🇬🇧 English

**Key Philosophy:** Instead of sending large voice recordings, the application processes speech entirely on-device, sends compact text payloads over peer-to-peer connections, and synthesizes text back to speech on the receiving phone.

### **Planned User Modes**

| Mode | Description |
|------|-------------|
| **Push-to-Talk (PTT)** | Microphone capture controlled by button press (walkie-talkie style) |
| **Phone Mode** | Hands-free monitoring with voice activity detection (VAD) |
| **Emergency Alerts** | High-volume alert playback for distress messages |

---

## ✨ Current Features

- ✅ **Offline Speech-to-Text (STT)** with Sherpa-ONNX
- ✅ **Real-time Voice Activity Detection (VAD)** with Silero
- ✅ **Multi-language STT routing** (IndicConformer for Indian languages, Vosk for English)
- ✅ **Wi-Fi Direct (P2P) Networking**
- ✅ **Microphone Recording & Audio Playback**
- ✅ **Runtime Permission Handling**
- ✅ **Text-to-Speech Synthesis** (TTS via Piper/Sherpa-ONNX)

## 🛠️ Technology Stack

| Component | Technology |
|-----------|-----------|
| **Framework** | Flutter + Dart (SDK `^3.5.0`) |
| **STT/TTS** | Sherpa-ONNX (quantized INT8 models) |
| **VAD** | Silero VAD on-device |
| **Audio I/O** | `record` + `audioplayers` |
| **P2P Networking** | `flutter_p2p_connection` (Wi-Fi Direct) |
| **Permissions** | `permission_handler` |
| **File Management** | `path_provider`, `archive` |

---

## 📁 Project Architecture

The application is organized into **service layers** with clear separation of concerns:

```
VaniLink/
├── lib/
│   ├── main.dart                        # App entry point & root widget
│   ├── speech_service.dart              # Legacy speech service (partial)
│   │
│   ├── ui/
│   │   └── walkie_talkie_screen.dart   # Main UI: PTT button & transcription display
│   │
│   ├── services/                        # Core service layer
│   │   ├── speech_to_text_service.dart # Master STT orchestrator (pipeline controller)
│   │   ├── language_router.dart         # Language switching & engine routing
│   │   ├── vad_service.dart             # Voice Activity Detection (Silero)
│   │   ├── audio_capture_service.dart   # Microphone capture & 30ms chunking
│   │   ├── stt_engine_interface.dart    # Abstract STT engine interface
│   │   ├── indic_conformer_stt.dart     # IndicConformer INT8 (Indian languages)
│   │   └── vosk_stt.dart                # Vosk STT (English)
│   │
│   ├── models/
│   │   └── message_payload.dart         # Message data model (text + metadata)
│   │
│   ├── audio/
│   │   └── microphone_handler.dart      # Low-level microphone recording
│   │
│   └── networking/
│       └── p2p_manager.dart             # Wi-Fi Direct (P2P) connection manager
│
├── assets/
│   └── models/
│       ├── stt/
│       │   ├── indic/                  # IndicConformer ONNX + tokens
│       │   │   ├── model.int8.onnx    # Quantized Indic STT model
│       │   │   └── tokens.txt          # Token vocabulary
│       │   └── english/                # Vosk ONNX + tokens
│       │       ├── model.onnx
│       │       └── tokens.txt
│       └── tts/
│           ├── hi/                     # Hindi TTS (Piper)
│           ├── en/                     # English TTS
│           ├── mr/                     # Marathi TTS
│           └── [ta, te, kn, ml, gu, pa, bn]/  # Other languages
│
├── test/
│   └── widget_test.dart                # Flutter widget & integration tests
│
├── android/                            # Native Android project
│   ├── app/
│   │   └── src/main/
│   │       ├── AndroidManifest.xml    # Permissions: RECORD_AUDIO, INTERNET, etc.
│   │       └── java/com/example/itantra/MainActivity.kt
│   └── build.gradle.kts
│
├── pubspec.yaml                        # Dependencies & asset registration
├── pubspec.lock                        # Locked dependency versions
├── analysis_options.yaml               # Dart linter configuration
└── README.md                           # This file
```

---

## 🏗️ System Architecture

### **Speech-to-Text Pipeline (STT)**

```
┌──────────────────┐
│  Microphone      │  16 kHz, 16-bit PCM, mono
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Audio Capture   │  30ms chunking (480 samples @ 16kHz)
│  Service         │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Silero VAD      │  Real-time voice activity detection
│  Service         │  Outputs: VAD state, speech probability
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Audio Buffer    │  Accumulates samples during speech
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Language Router │  Selects active STT engine based on language
│                  │  English → Vosk, Indian → IndicConformer
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  STT Engine      │  Offline ONNX inference
│  (Vosk or        │
│   IndicConformer)│
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Transcribed     │  Text output (e.g., "नमस्ते")
│  Text Stream     │
└──────────────────┘
```

### **Key Service Classes**

| Class | Purpose |
|-------|---------|
| **SpeechToTextService** | Master orchestrator; owns the entire STT pipeline |
| **AudioCaptureService** | Reads from microphone, chunks into 30ms frames |
| **VadService** | Silero VAD; detects speech start/end, buffers audio segments |
| **SttLanguageRouter** | Routes speech segments to appropriate STT engine |
| **IndicConformerSttEngine** | Transcribes Indian languages (Hindi, Tamil, etc.) |
| **VoskSttEngine** | Transcribes English |
| **P2PManager** | Manages Wi-Fi Direct connections & message transport |
| **MessagePayload** | DTO for transcribed text + metadata |

---

## 🚀 Setup & Installation

### **Prerequisites**

- Flutter SDK: `^3.5.0`
- Android SDK: API 21+ (recommended 33+)
- Dart SDK: `^3.5.0`

### **1. Clone the Repository**

```bash
git clone https://github.com/yourusername/VaniLink.git
cd VaniLink
```

### **2. Install Flutter Dependencies**

```bash
flutter pub get
```

### **3. Download ONNX Models** ⚠️

The app requires ONNX models to run. Place them in these directories:

**STT Models:**
```
assets/models/stt/indic/
├── model.int8.onnx      # IndicConformer quantized model
└── tokens.txt           # Token vocabulary

assets/models/stt/english/
├── model.onnx           # Vosk English model
└── tokens.txt
```

**TTS Models (Optional):**
```
assets/models/tts/hi/
├── hi_model.onnx
├── tokens.txt
└── espeak_data.zip      # eSpeak phoneme data

assets/models/tts/en/    # Similar structure for English
...
```

Download models from:
- **IndicConformer:** [Sherpa-ONNX Releases](https://github.com/k2-fsa/sherpa-onnx/releases)
- **Vosk Models:** [Vosk Models](https://alphacephei.com/vosk/models)
- **Piper TTS:** [Piper Releases](https://github.com/rhasspy/piper/releases)

### **4. Build & Run**

**On Emulator:**
```bash
flutter run -d emulator-5554
```

**On Physical Device:**
```bash
# Connect device via USB, enable Developer Mode
flutter run
```

**Run Tests:**
```bash
flutter test
```

---

## 📋 Android Permissions

The app requires the following permissions (defined in `AndroidManifest.xml`):

| Permission | Purpose |
|-----------|---------|
| `RECORD_AUDIO` | Microphone access for STT |
| `MODIFY_AUDIO_SETTINGS` | Volume & audio routing control |
| `INTERNET` | P2P socket communication |
| `ACCESS_WIFI_STATE` | Query Wi-Fi state |
| `CHANGE_WIFI_STATE` | Wi-Fi Direct setup |
| `CHANGE_NETWORK_STATE` | Network connection management |
| `ACCESS_FINE_LOCATION` | Wi-Fi Direct discovery (Android 10+) |
| `NEARBY_WIFI_DEVICES` | Wi-Fi Direct discovery (Android 13+) |
| `FOREGROUND_SERVICE` | Background audio processing |
| `FOREGROUND_SERVICE_MICROPHONE` | Foreground service microphone access |

All permissions are requested at runtime using `permission_handler`.

---

## 🧪 Testing

### **Run All Tests**

```bash
flutter test
```

### **Run Specific Test**

```bash
flutter test test/widget_test.dart -v
```

### **Test Coverage**

```bash
flutter test --coverage
```

---

## 📊 Component Responsibilities

| Component | Responsibility |
|-----------|-----------------|
| **UI Layer** | `WalkieTalkieScreen`: displays transcription, PTT button, VAD visualization |
| **Service Layer** | Orchestrates STT pipeline; exposes streams for real-time updates |
| **Model Layer** | `MessagePayload` for P2P message serialization |
| **Audio Layer** | Low-level microphone access & PCM chunking |
| **Network Layer** | P2P connection management & message transport |

---

## 🔧 Development Workflow

### **Code Style**

- Format code: `dart format lib/`
- Lint: `flutter analyze`
- Follow Dart Style Guide & effective Dart

### **Adding a New Language**

1. Create model directory: `assets/models/stt/{language}/`
2. Add ONNX model + tokens
3. Update `AppLanguage` enum in `language_router.dart`
4. Test language switching via `setLanguage()`

### **Extending STT Engine**

1. Implement `SttEngineInterface`
2. Register in `SttLanguageRouter.activeEngine` switch
3. Initialize in `SttLanguageRouter.init()`

---

## 🐛 Known Limitations

- ⚠️ Sherpa-ONNX and Vosk models must be manually downloaded
- ⚠️ P2P networking is a stub (TODO: implement)
- ⚠️ TTS initialization is incomplete (requires model setup)
- ⚠️ No persistent message history yet
- ⚠️ No end-to-end encryption (planned feature)

---

## 📝 Roadmap

- [ ] Implement full P2P Wi-Fi Direct communication
- [ ] Complete TTS integration with Piper
- [ ] Add message persistence (SQLite)
- [ ] End-to-end encryption (Signal protocol)
- [ ] Group chat support
- [ ] Message read receipts
- [ ] Audio visualization during recording
- [ ] Language auto-detection
- [ ] Emergency broadcast mode

---

## 📚 References

- [Sherpa-ONNX Documentation](https://github.com/k2-fsa/sherpa-onnx)
- [Flutter Documentation](https://flutter.dev/docs)
- [Wi-Fi Direct Basics](https://developer.android.com/guide/topics/connectivity/wifip2p)
- [Dart Language Guide](https://dart.dev/guides)

---

## 📄 License

[Add your license here]

---

## 👥 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit changes: `git commit -m "Add your feature"`
4. Push to branch: `git push origin feature/your-feature`
5. Open a Pull Request

---

## 💡 Questions & Support

For questions, feature requests, or bug reports, please open an issue on the GitHub repository.

---

**Built with ❤️ for offline, privacy-first voice communication.**

### Runtime flow

1. `main.dart` starts the Flutter application.
2. `SpeechService.initModels()` loads the bundled STT and TTS models.
3. Recorded 16 kHz PCM samples are passed to `transcribeAudio()`.
4. Text is exchanged with a peer over the P2P connection.
5. Received text is passed to `synthesizeSpeech()` and played locally.

## Planned Technical Architecture

The current implementation establishes the Flutter shell, audio dependencies, P2P dependency, and Sherpa-ONNX speech service. The following components describe the planned end-to-end architecture:

### Offline speech pipeline

- **Voice activity detection:** Add a lightweight Silero VAD model to process microphone input in short chunks and activate STT only when speech is detected.
- **Speech-to-text:** Use quantized IndicConformer models for Indian languages, with an optimized English model where appropriate.
- **Text-to-speech:** Use compact VITS/Piper and MMS TTS models for the supported languages.
- **Resource limits:** Keep inference local and optimize model loading and execution for mid-range Android devices.

### Peer-to-peer networking

- Use Wi-Fi Direct as the primary transport for local communication.
- Add Bluetooth as a short-range, low-power fallback where supported.
- Add network service discovery so peers can find the group owner without manual IP and port configuration.
- Pause outgoing messages and buffer them while a disconnected peer is reconnecting.
- Add peer authentication with a secure challenge-response handshake before resuming delivery.

### Bandwidth and resilience goals

Transmitting text instead of raw audio is intended to reduce message size substantially and avoid cloud round trips. The target is low-latency local communication with privacy preserved by keeping VAD, STT, TTS, and message processing on-device.

## Prerequisites

- [Git](https://git-scm.com/downloads)
- [Flutter SDK](https://docs.flutter.dev/get-started/install), compatible with Dart `3.5.0` or newer
- VS Code or Android Studio
- Android SDK and an emulator or physical Android device
- USB debugging enabled when using a physical device

Check the local Flutter installation:

```bash
flutter doctor
```

## Copy the Repository

```bash
git clone https://github.com/Ved0019/VaniLink.git
cd VaniLink
```

To update an existing checkout later:

```bash
git pull origin main
```

## Install and Run

From the repository root, install dependencies and list available devices:

```bash
flutter pub get
flutter devices
```

Run on the default device or emulator:

```bash
flutter run
```

Run on a specific device:

```bash
flutter run -d <device-id>
```

Keep the model paths under `assets/models/` unchanged. They are registered in `pubspec.yaml` and loaded at runtime.

## Android Notes

Speech and peer-to-peer features require runtime permissions. Grant microphone and nearby-device/location permissions when Android requests them. Wi-Fi Direct should be tested on physical Android devices because emulators generally cannot reproduce device-to-device networking reliably.

## Validate Changes

```bash
flutter analyze
flutter test
```

## Contributing

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-change`.
3. Make and validate your changes.
4. Commit and push the branch.
5. Open a pull request with a short description and test details.
