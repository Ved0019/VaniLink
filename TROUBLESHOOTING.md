# VaniLink - Quick Troubleshooting Guide

## Issue 1: Sherpa-ONNX TTS Error: "Errors in config"

### Error Message:
```
W/sherpa-onnx(21749): /home/runner/work/sherpa-onnx/sherpa-onnx/sherpa-onnx/c-api/c-api.cc:SherpaOnnxCreateOfflineTts:1624
W/sherpa-onnx(21749): Errors in config
```

### Root Cause:
TTS model configuration is incomplete. Usually missing or incorrect `vits-data-dir` (eSpeak-ng phoneme data path).

### Solutions (in order of priority):

**Solution 1: Download & Extract eSpeak-ng Data**
```bash
# Download from Piper releases
wget https://github.com/rhasspy/piper/releases/download/v1.2.0/espeak-ng-data.tar.gz
tar xzf espeak-ng-data.tar.gz

# Place in app cache directory
mkdir -p ~/.vanilink_cache/espeak-ng-data
cp -r espeak-ng-data/* ~/.vanilink_cache/espeak-ng-data/
```

**Solution 2: Use Pre-packaged Piper Models**
```bash
# Piper includes espeak-ng data in release tarballs
wget https://github.com/rhasspy/piper/releases/download/v1.2.0/en_US-glow-tts-1.1-release.tar.gz
tar xzf en_US-glow-tts-1.1-release.tar.gz

# File structure:
# en_US-glow-tts-1.1-release/
# ├── model.onnx
# ├── tokens.txt
# └── espeak-ng-data/         ← Use this directory path in SpeechService
```

**Solution 3: Disable TTS Initialization (Development Only)**
```dart
// In speech_service.dart, comment out TTS initialization
// await _loadTts('en');  // Skip TTS for testing UI
```

### Verification Checklist:
- [ ] eSpeak-ng data directory exists and is not empty
- [ ] TTS model.onnx file is in correct location
- [ ] tokens.txt file is present
- [ ] Logs show "✅ TTS initialized" instead of warning

---

## Issue 2: Sherpa-ONNX STT Error: "vocab_size does not exist"

### Error Message:
```
W/sherpa-onnx(21749): /home/runner/work/sherpa-onnx/sherpa-onnx/sherpa-onnx/csrc/offline-nemo-enc-dec-ctc-model.cc:Init:122
W/sherpa-onnx(21749): 'vocab_size' does not exist in the metadata
```

### Root Cause:
STT model metadata is incomplete or corrupted. Model was not properly downloaded or is incompatible.

### Solutions (in order of priority):

**Solution 1: Download Official Sherpa-ONNX Models**
```bash
# Only use models from official releases
https://github.com/k2-fsa/sherpa-onnx/releases

# Look for "asr-models" or "ctc-models" releases
# These have properly formatted metadata

# Example: IndicConformer for Indian languages
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-indic-conformer-ctc-onnx-model.tar.bz2
tar xjf sherpa-onnx-indic-conformer-ctc-onnx-model.tar.bz2
```

**Solution 2: Use Vosk Models for English**
```bash
# If IndicConformer fails, use Vosk
https://alphacephei.com/vosk/models

# Download: vosk-model-small-en-us-0.4
wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.4.zip
unzip vosk-model-small-en-us-0.4.zip
```

**Solution 3: Regenerate Model Metadata**
If you have a custom model, add metadata:
```bash
# Model metadata should include:
# - vocab_size: number of phonemes/characters
# - num_decoder_layers: decoder architecture
# - output_dim: output dimension
# - sample_rate: 16000 (for audio)

# See: https://github.com/k2-fsa/sherpa-onnx/blob/master/docs/model-zoo.md
```

### Verification Checklist:
- [ ] Model is from official Sherpa-ONNX releases
- [ ] model.int8.onnx file is present
- [ ] tokens.txt file is present and not empty
- [ ] Logs show "✅ STT initialized" instead of warning

---

## Issue 3: "Lost connection to device"

### Error Message:
```
Lost connection to device.
```

### Root Cause:
App crashed due to unhandled exception, usually model initialization failure.

### Solutions:

**Solution 1: Check Detailed Logs**
```bash
adb logcat | grep -E "sherpa|flutter|VaniLink" -A 2
# Look for stack traces showing exactly what failed
```

**Solution 2: Test Without Models**
```dart
// Comment out model initialization for debugging
// _sttReady = false;
// _ttsReady = false;
```

**Solution 3: Increase Cache Directory**
```bash
# Ensure sufficient storage for models
# Models can be 100-300 MB each
adb shell df /data/data/com.example.itantra/cache
```

---

## Issue 4: App Runs but STT/TTS Not Working

### Symptoms:
- UI loads fine
- No error messages
- Pressing PTT button does nothing
- No transcription appears

### Diagnosis:

**Check 1: Verify Model Status**
```dart
// In any service, log the status:
print('STT Ready: ${SpeechService().isInitialized}');

// Should print: STT Ready: true (if models loaded)
```

**Check 2: Verify Asset Paths**
```bash
# List all assets in app
find assets/models/ -type f | sort

# Should show:
# assets/models/stt/indic/model.int8.onnx
# assets/models/stt/indic/tokens.txt
# assets/models/tts/en/model.onnx
# assets/models/tts/en/tokens.txt
```

**Check 3: Verify pubspec.yaml Registration**
```yaml
flutter:
  assets:
    - assets/models/stt/indic/
    - assets/models/stt/english/
    - assets/models/tts/en/
    # Make sure all directories are listed!
```

---

## Quick Diagnostic Script

```bash
#!/bin/bash
# Run this to check VaniLink setup

echo "=== VaniLink Setup Diagnosis ==="
echo ""

echo "1. Checking Flutter environment..."
flutter --version

echo ""
echo "2. Checking model directory structure..."
find assets/models -type f 2>/dev/null | wc -l
echo "   Files found: $(find assets/models -type f 2>/dev/null | wc -l)"

echo ""
echo "3. Checking app connectivity..."
adb devices

echo ""
echo "4. Getting recent app logs..."
adb logcat -d | grep -E "sherpa|flutter" | tail -20

echo ""
echo "5. Checking app storage..."
adb shell "du -sh /data/data/com.example.itantra/cache"

echo ""
echo "=== Diagnosis Complete ==="
```

---

## Working Setup Checklist

- [ ] Flutter SDK installed (`flutter --version`)
- [ ] Android device/emulator connected (`adb devices`)
- [ ] Model directory structure correct
- [ ] All required model files present (not empty)
- [ ] pubspec.yaml assets updated
- [ ] `flutter pub get` run
- [ ] `flutter clean && flutter run` executed
- [ ] App launches without crashes
- [ ] Logs show "✅ initialized" messages
- [ ] PTT button responds to press

---

## Still Having Issues?

### Collect Debug Information:

1. **Full Log Output**
   ```bash
   flutter run 2>&1 | tee vanilink_debug.log
   ```

2. **Logcat Output**
   ```bash
   adb logcat > device_logs.txt
   # Reproduce error, wait 10 seconds, Ctrl+C
   ```

3. **Model File Verification**
   ```bash
   ls -lah assets/models/stt/indic/
   ls -lah assets/models/tts/en/
   ```

4. **File Integrity Check**
   ```bash
   file assets/models/stt/indic/model.int8.onnx
   # Should output: ONNX model data
   ```

### Contact Support:
Include in issue report:
- Device model and Android version
- Full error logs (see above)
- Model file sizes
- Output of setup checklist

---

**Remember**: The app is fully functional without ONNX models for testing UI/UX. Models are only required for actual STT/TTS functionality.
