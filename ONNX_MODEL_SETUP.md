# Sherpa-ONNX Model Setup Guide for VaniLink

## Current Status

✅ **App Structure**: Fully implemented
✅ **UI/UX**: Complete with Editorial design
✅ **Services**: STT, TTS, P2P integrated
❌ **ONNX Models**: Not configured (causing runtime warnings)

---

## Errors Observed

### 1. **TTS Error: `--vits-data-dir` Configuration**

```
W/sherpa-onnx(21749): /home/runner/work/sherpa-onnx/sherpa-onnx/sherpa-onnx/c-api/c-api.cc:SherpaOnnxCreateOfflineTts:1624
W/sherpa-onnx(21749): Errors in config
```

**Cause**: TTS VITS model needs eSpeak-ng phoneme data directory.

**Solution**: 
1. Download Piper TTS model + espeak-ng data
2. Extract espeak-ng-data.zip
3. Set correct path in `SpeechService._loadTts()`

### 2. **STT Error: Missing `vocab_size` in Metadata**

```
W/sherpa-onnx(21749): /home/runner/work/sherpa-onnx/sherpa-onnx/sherpa-onnx/csrc/offline-nemo-enc-dec-ctc-model.cc:Init:122
W/sherpa-onnx(21749): 'vocab_size' does not exist in the metadata
```

**Cause**: STT model metadata is incomplete or corrupted.

**Solution**:
1. Download verified IndicConformer or Vosk model
2. Ensure model has complete metadata
3. Use compatible Sherpa-ONNX version

---

## Model Download Sources

### STT Models

#### IndicConformer (Indian Languages)
- **Source**: [Sherpa-ONNX Releases](https://github.com/k2-fsa/sherpa-onnx/releases)
- **Models**: Pre-built quantized INT8 models
- **Location**: `assets/models/stt/indic/`
- **Files Required**:
  ```
  model.int8.onnx    (STT model)
  tokens.txt         (Vocabulary)
  ```

#### Vosk (English)
- **Source**: [Vosk Models](https://alphacephei.com/vosk/models)
- **Location**: `assets/models/stt/english/`
- **Files Required**:
  ```
  model.onnx         (STT model)
  tokens.txt         (Vocabulary)
  ```

### TTS Models

#### Piper TTS
- **Source**: [Piper GitHub Releases](https://github.com/rhasspy/piper/releases)
- **Location**: `assets/models/tts/{language}/`
- **Files Required** (per language):
  ```
  model.onnx                 (TTS model)
  tokens.txt                 (Phoneme tokens)
  espeak-ng-data.zip         (eSpeak phoneme data)
  ```

#### Supported Languages for TTS:
- `en/` - English
- `hi/` - Hindi
- `mr/` - Marathi
- `ta/` - Tamil
- `te/` - Telugu
- `kn/` - Kannada
- `ml/` - Malayalam
- `gu/` - Gujarati
- `pa/` - Punjabi
- `bn/` - Bengali

---

## Step-by-Step Setup Instructions

### 1. **Download STT Models**

```bash
# Option A: Use Sherpa-ONNX pre-built models
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-indic-conformer-ctc-onnx-model.tar.bz2
tar xjf sherpa-onnx-indic-conformer-ctc-onnx-model.tar.bz2

# Copy to project
mkdir -p assets/models/stt/indic
cp sherpa-onnx-*/model.int8.onnx assets/models/stt/indic/
cp sherpa-onnx-*/tokens.txt assets/models/stt/indic/
```

### 2. **Download TTS Models**

```bash
# Download Piper TTS (Example: English)
wget https://github.com/rhasspy/piper/releases/download/v1.2.0/en_US-glow-tts-1.1-release.tar.gz
tar xzf en_US-glow-tts-1.1-release.tar.gz

# Extract and organize
mkdir -p assets/models/tts/en
cp en_US-glow-tts-1.1-release/*.onnx assets/models/tts/en/model.onnx
cp en_US-glow-tts-1.1-release/tokens.txt assets/models/tts/en/
cp en_US-glow-tts-1.1-release/espeak-ng-data.zip assets/models/tts/en/

# Unzip espeak data
cd assets/models/tts/en
unzip espeak-ng-data.zip
rm espeak-ng-data.zip
cd ../../../..
```

### 3. **Verify Model Structure**

```
assets/models/
├── stt/
│   ├── indic/
│   │   ├── model.int8.onnx        ✓ Required
│   │   └── tokens.txt              ✓ Required
│   └── english/
│       ├── model.onnx              ✓ Required
│       └── tokens.txt              ✓ Required
└── tts/
    ├── en/
    │   ├── model.onnx              ✓ Required
    │   ├── tokens.txt              ✓ Required
    │   └── espeak-ng-data/         ✓ Unzipped directory (NOT .zip)
    ├── hi/
    │   ├── model.onnx
    │   ├── tokens.txt
    │   └── espeak-ng-data/
    └── [other languages...]
```

### 4. **Update pubspec.yaml Asset Paths**

```yaml
flutter:
  assets:
    # STT Models
    - assets/models/stt/indic/
    - assets/models/stt/english/
    # TTS Models (all languages)
    - assets/models/tts/en/
    - assets/models/tts/hi/
    - assets/models/tts/mr/
    - assets/models/tts/ta/
    - assets/models/tts/te/
    - assets/models/tts/kn/
    - assets/models/tts/ml/
    - assets/models/tts/gu/
    - assets/models/tts/pa/
    - assets/models/tts/bn/
```

### 5. **Rebuild App**

```bash
flutter clean
flutter pub get
flutter run
```

---

## Troubleshooting

### Issue: "Errors in config" (TTS)

**Cause**: eSpeak data directory path is incorrect or directory doesn't exist.

**Fix in `lib/speech_service.dart`**:
```dart
// Ensure dataDir points to extracted espeak-ng-data directory, NOT the zip file
final dataDir = await _extractAndUnzipAsset('assets/models/tts/$langCode/espeak-ng-data.zip');
```

### Issue: "vocab_size does not exist" (STT)

**Cause**: Model metadata is incomplete.

**Verify**:
- Download from official Sherpa-ONNX releases only
- Don't use modified or custom models without proper metadata
- Check model compatibility with current Sherpa-ONNX version

### Issue: "Lost connection to device"

**Likely Cause**: App crash due to missing models.

**Fix**:
- Ensure models are placed in correct directories
- Check logcat for detailed errors: `adb logcat | grep sherpa`
- Models are optional - app should gracefully degrade

---

## Model File Sizes (Approximate)

| Model | Language | Size | Notes |
|-------|----------|------|-------|
| IndicConformer | All Indic | 50-80 MB | INT8 quantized |
| Vosk | English | 40-50 MB | Pre-quantized |
| Piper VITS | Per language | 50-200 MB | Varies by quality |
| eSpeak-ng Data | All | 5-10 MB | Extracted |

**Total App Size**: ~50-100 MB (depends on languages included)

---

## For Development/Testing

### Option A: Run Without Models (Graceful Degradation)

The app is designed to work without ONNX models:
- UI loads successfully
- STT/TTS functionality skipped with log messages
- P2P and chat features still functional

### Option B: Use Placeholder Models (For Testing)

Create minimal test models (not recommended for production):
```dart
// In speech_service.dart
_sttReady = false;  // Skip STT if models unavailable
_ttsReady = false;  // Skip TTS if models unavailable
```

---

## Next Steps

1. **Download Models**: Follow Step-by-Step Setup above
2. **Extract Models**: Unzip and organize into asset directories
3. **Rebuild App**: `flutter clean && flutter run`
4. **Verify Initialization**: Check logs for ✅ success messages
5. **Test PTT**: Record speech and verify transcription

---

## References

- [Sherpa-ONNX Documentation](https://github.com/k2-fsa/sherpa-onnx)
- [Piper TTS Models](https://github.com/rhasspy/piper)
- [Vosk Models](https://alphacephei.com/vosk/models)
- [Model Metadata Format](https://github.com/k2-fsa/sherpa-onnx/blob/master/docs/python-api-for-offline-speech-recognition.md)

---

**Status**: Ready for model setup. App compiles and runs successfully. Models are optional for testing UI/UX.
