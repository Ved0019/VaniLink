import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vanilink/services/indic_conformer_stt.dart';
import 'package:vanilink/services/stt_engine_interface.dart';
import 'package:vanilink/services/vad_service.dart';
import 'package:vanilink/services/vosk_stt.dart';

/// Supported target languages in iTantra
enum AppLanguage {
  english,
  hindi,
  gujarati,
  marathi,
  kannada,
  malayalam,
  tamil,
  telugu,
  odia,
  bengali,
}

extension AppLanguageExtension on AppLanguage {
  String get displayName {
    switch (this) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.hindi:
        return 'Hindi';
      case AppLanguage.gujarati:
        return 'Gujarati';
      case AppLanguage.marathi:
        return 'Marathi';
      case AppLanguage.kannada:
        return 'Kannada';
      case AppLanguage.malayalam:
        return 'Malayalam';
      case AppLanguage.tamil:
        return 'Tamil';
      case AppLanguage.telugu:
        return 'Telugu';
      case AppLanguage.odia:
        return 'Odia';
      case AppLanguage.bengali:
        return 'Bengali';
    }
  }

  String get code {
    switch (this) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.hindi:
        return 'hi';
      case AppLanguage.gujarati:
        return 'gu';
      case AppLanguage.marathi:
        return 'mr';
      case AppLanguage.kannada:
        return 'kn';
      case AppLanguage.malayalam:
        return 'ml';
      case AppLanguage.tamil:
        return 'ta';
      case AppLanguage.telugu:
        return 'te';
      case AppLanguage.odia:
        return 'or';
      case AppLanguage.bengali:
        return 'bn';
    }
  }
}

/// Router responsible for dispatching VAD speech segments to either
/// Vosk (English) or IndicConformer INT8 (Indian Languages).
class SttLanguageRouter {
  AppLanguage _currentLanguage = AppLanguage.english;
  late final IndicConformerSttEngine _indicEngine;
  final VoskSttEngine _voskEngine;

  SttLanguageRouter({
    IndicConformerSttEngine? indicEngine,
    VoskSttEngine? voskEngine,
  })  : _voskEngine = voskEngine ?? VoskSttEngine() {
    _indicEngine = indicEngine ?? IndicConformerSttEngine(language: _currentLanguage);
  }

  /// Current selected language
  AppLanguage get currentLanguage => _currentLanguage;

  /// Active STT engine instance based on current language selection
  SttEngineInterface get activeEngine =>
      (_currentLanguage == AppLanguage.english) ? _voskEngine : _indicEngine;

  /// Display name of the active STT engine
  String get activeEngineName => (_currentLanguage == AppLanguage.english)
      ? 'Vosk STT (English)'
      : 'IndicConformer INT8 (${_currentLanguage.displayName})';

  /// Updates selected target language
  void setLanguage(AppLanguage language) {
    if (_currentLanguage != language) {
      _currentLanguage = language;
      debugPrint('STT Language routed to: ${language.displayName} -> Engine: $activeEngineName');
    }
  }

  /// Initializes both engines
  Future<void> init() async {
    try {
      await _voskEngine.init();
    } catch (e) {
      debugPrint('Vosk init note: $e');
    }

    try {
      await _indicEngine.init();
    } catch (e) {
      debugPrint('IndicConformer init note: $e');
    }
  }

  /// Transcribes speech segment using the appropriate engine for current language
  Future<String> transcribeSegment(SpeechSegment segment) async {
    final engine = activeEngine;
    if (!engine.isInitialized) {
      try {
        await engine.init();
      } catch (e) {
        debugPrint('Engine auto-init note: $e');
      }
    }

    return await engine.transcribeSegment(segment);
  }

  /// Cleanly disposes engine resources
  void dispose() {
    _indicEngine.dispose();
    _voskEngine.dispose();
  }
}
