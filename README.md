# iTantra

iTantra is an offline, peer-to-peer walkie-talkie Flutter application with on-device Indic speech recognition and speech synthesis. Audio can be captured locally, converted to text with bundled ONNX models, sent over Wi-Fi Direct, and synthesized on the receiving device without a cloud service.

## Features

- Offline speech-to-text (STT) with Sherpa-ONNX.
- Offline text-to-speech (TTS) with bundled ONNX/Piper-compatible models.
- Wi-Fi Direct peer-to-peer communication.
- Microphone recording and audio playback.
- Runtime permission handling.
- Flutter targets for Android, iOS, Web, Windows, macOS, and Linux where the required plugins are supported.

## Technology

- Flutter and Dart.
- Dart SDK `^3.5.0`.
- `sherpa_onnx` for local STT/TTS inference.
- `record` and `audioplayers` for audio input and output.
- `flutter_p2p_connection` for Wi-Fi Direct networking.
- `permission_handler` for runtime permissions.

## Project Architecture

The project follows Flutter's standard platform layout. Application behavior belongs in `lib/`, while each platform directory contains its native runner and build configuration.

```text
iTantra/
├── lib/
│   ├── main.dart             # Flutter application entry point and UI
│   └── speech_service.dart   # Singleton service for offline STT and TTS
├── assets/
│   └── models/
│       ├── stt/              # STT ONNX model and tokens
│       └── tts/              # TTS ONNX model, tokens, and espeak data
├── test/
│   └── widget_test.dart      # Flutter widget tests
├── android/                  # Android project and Gradle files
├── ios/                      # iOS project and native runner
├── web/                      # Web entrypoint and manifest
├── linux/                    # Linux runner and CMake configuration
├── macos/                    # macOS runner and Xcode configuration
├── windows/                  # Windows runner and CMake configuration
├── pubspec.yaml              # Dependencies and asset registration
└── analysis_options.yaml     # Dart analyzer and lint configuration
```

### Runtime flow

1. `main.dart` starts the Flutter application.
2. `SpeechService.initModels()` loads the bundled STT and TTS models into memory.
3. Recorded 16 kHz PCM samples are passed to `transcribeAudio()`.
4. Text is exchanged with a peer over the P2P connection.
5. Received text is passed to `synthesizeSpeech()` and played back locally.

## Prerequisites

Install the following on your machine:

- [Git](https://git-scm.com/downloads)
- [Flutter SDK](https://docs.flutter.dev/get-started/install), with Dart `3.5.0` or newer compatible with the project constraint
- An IDE such as [VS Code](https://code.visualstudio.com/) or Android Studio
- For Android: Android SDK, emulator or physical device, and USB debugging if using a device
- For iOS/macOS: macOS with Xcode and CocoaPods

Verify the Flutter installation:

```bash
flutter doctor
```

Resolve every required issue reported for the platform you intend to run.

## Copy the Repository

Clone the repository and enter its directory:

```bash
git clone https://github.com/Ved0019/iTantra.git
cd iTantra
```

To work on your own fork, replace the URL with your fork's URL. To update an existing checkout later:

```bash
git pull origin main
```

## Install and Run

From the repository root, fetch Dart and Flutter dependencies:

```bash
flutter pub get
```

List available devices:

```bash
flutter devices
```

Run on the default connected device or emulator:

```bash
flutter run
```

Run on a specific device by using the device ID shown by `flutter devices`:

```bash
flutter run -d <device-id>
```

Keep the bundled model paths under `assets/models/` unchanged. They are registered in `pubspec.yaml` and loaded at runtime.

## Android Notes

Speech and peer-to-peer features require runtime permissions. Grant microphone and nearby-device/location permissions when Android requests them. Wi-Fi Direct behavior must be tested on a physical Android device; Android emulators generally cannot reproduce device-to-device networking reliably.

## Validate Changes

Run the analyzer and tests before opening a pull request:

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

## Technology

- Flutter and Dart.
- Dart SDK `^3.5.0`.
- `sherpa_onnx` for local STT/TTS inference.
- `record` and `audioplayers` for audio input and output.
- `flutter_p2p_connection` for Wi-Fi Direct networking.
- `permission_handler` for runtime permissions.

## Project Architecture

The project follows Flutter's standard platform layout. Application behavior belongs in `lib/`, while each platform directory contains its native runner and build configuration.

For a development build, keep the bundled model paths under `assets/models/` unchanged. They are registered in `pubspec.yaml` and loaded at runtime.

## Android Notes

Speech and peer-to-peer features require runtime permissions. Grant microphone and nearby-device/location permissions when Android requests them. Wi-Fi Direct behavior must be tested on a physical Android device; Android emulators generally cannot reproduce device-to-device networking reliably.

## Validate Changes

Run the analyzer and tests before opening a pull request:

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

## 📁 Project Structure

Here is a quick overview of the core directories to help you find your way around the codebase:

* `lib/`: Contains the core application code.
  * `main.dart`: Entry point of the application.
  * `speech_service.dart`: Handles speech recognition and voice services.
* `android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/`: Platform-specific configurations.

---

## 🤝 How to Contribute

We love contributions! If you want to help build iTantra, follow these steps:

1. **Fork the Project**
2. **Create your Feature Branch** (`git checkout -b feature/AmazingFeature`)
3. **Commit your Changes** (`git commit -m 'Add some AmazingFeature'`)
4. **Push to the Branch** (Based on the project files provided, your repository `iTantra` is structured as a **Flutter cross-platform application** (featuring directories for `android`, `ios`, `linux`, `macos`, `windows`, `web`, and core logic in `lib/` with files like `main.dart` and `speech_service.dart`)[cite: 1]. 

### Is the Code Structure Good?
* **Standard Layout:** Yes, it follows the canonical Flutter project layout out-of-the-box[cite: 1]. 
* **Modular Potential:** You already have a dedicated `speech_service.dart` file alongside `main.dart`, which indicates you are separating concerns (handling speech features separately from UI)[cite: 1]. To keep the code clean as you scale, make sure to organize your widgets, models, and screens into separate folders inside `lib/`.

---

### How to Write a README for Collaboration
To get people to clone your repository and start building with you, your `README.md` needs to be welcoming, clear, and instructive. 

Here is a ready-to-use template tailored for your Flutter project. You can copy this, paste it into your `README.md`, and adjust any specifics:


# iTantra 🎙️🚀

`iTantra` is a cross-platform Flutter application[cite: 1] designed to incorporate speech capabilities[cite: 1] (powered by `speech_service.dart`)[cite: 1]. We are building an open-source community to expand its features across mobile, desktop, and web.

---

## 🛠️ Tech Stack
* **Framework:** [Flutter](https://flutter.dev/) (Dart)[cite: 1]
* **Target Platforms:** Android, iOS, Web, Windows, macOS, Linux[cite: 1]

---

## 🏁 Getting Started (For Contributors)

Follow these steps to set up your local development environment and run the project.

### Prerequisites
Make sure you have the following installed:
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable version recommended)
* Git

### 1. Clone the Repository
```bash
git clone https://github.com/Ved0019/iTantra.git
cd iTantra

2. Install Dependencies
Fetch all required packages listed in pubspec.yaml:

Bash
flutter pub get
3. Run the App
Connect a device or launch an emulator, then execute:

Bash
flutter run
📂 Project Structure
A quick look at how the code is organized:

Plaintext
lib/
│
├── main.dart             # Application entry point & root widget
└── speech_service.dart   # Core logic for speech functionalities
android/ /ios/ /web/      # Platform-specific configurations
🤝 How to Contribute
We love contributions! Whether it's fixing bugs, improving UI, or adding new features:

Fork the repository.

Create a new branch for your feature (git checkout -b feature/AmazingFeature).

Commit your changes (git commit -m 'Add some AmazingFeature').

Push to the branch (git push origin feature/AmazingFeature).

Open a Pull Request.
