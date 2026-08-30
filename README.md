# VaniLink

VaniLink is an offline, peer-to-peer Android walkie-talkie application built with Flutter. It uses on-device Indic speech recognition and speech synthesis, so audio can be processed locally without a cloud service.

## Product Vision

VaniLink is intended to become a fully offline, local-first neural transceiver for voice communication across 10 target languages: Hindi, Gujarati, Marathi, Kannada, Malayalam, Tamil, Telugu, Odia, Bengali, and English.

Instead of sending large voice recordings, the application processes speech on the device, sends compact text payloads over a local peer-to-peer connection, and synthesizes the text back into speech on the receiving phone. This approach is designed to improve privacy, reduce bandwidth usage, and keep communication available when cellular or internet infrastructure is unavailable.

### Planned user modes

- **Push-to-talk:** Microphone capture is controlled by a physical or virtual PTT button.
- **Phone mode:** Hands-free monitoring uses voice activity detection to identify spoken sentences.
- **Emergency alerts:** High-volume alert playback for distress messages, subject to Android audio and permission rules.

## Features

- Offline speech-to-text and text-to-speech with Sherpa-ONNX.
- Wi-Fi Direct peer-to-peer communication.
- Microphone recording and audio playback.
- Runtime permission handling.

## Technology

- Flutter and Dart, with Dart SDK `^3.5.0`.
- `sherpa_onnx` for local STT/TTS inference.
- `record` and `audioplayers` for audio input and output.
- `flutter_p2p_connection` for Wi-Fi Direct networking.
- `permission_handler` for runtime permissions.

## Project Architecture

Application behavior belongs in `lib/`. The `android/` directory contains the native Android runner and Gradle configuration.

```text
VaniLink/
|-- lib/
|   |-- main.dart             # Flutter application entry point and UI
|   `-- speech_service.dart   # Offline STT and TTS service
|-- assets/
|   `-- models/
|       |-- stt/              # STT ONNX model and tokens
|       `-- tts/              # TTS ONNX model, tokens, and espeak data
|-- test/
|   `-- widget_test.dart      # Flutter widget tests
|-- android/                  # Android project and Gradle files
|-- pubspec.yaml              # Dependencies and asset registration
`-- analysis_options.yaml     # Dart analyzer and lint configuration
```

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
