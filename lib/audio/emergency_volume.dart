import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls Android audio stream volume for emergency alert mode.
/// Uses a MethodChannel to reach the native AudioManager.
///
/// When [activate] is called the device volume is pushed to maximum on
/// the STREAM_ALARM channel, which bypasses Do Not Disturb and cannot
/// be lowered by the hardware volume buttons until [deactivate] is called.
class EmergencyVolume {
  static const _channel = MethodChannel('vanilink/audio');

  static bool _isActive = false;
  static bool get isActive => _isActive;

  /// Pushes alarm stream to maximum volume.
  static Future<void> activate() async {
    try {
      await _channel.invokeMethod('setAlarmVolume');
      _isActive = true;
      debugPrint('EmergencyVolume: alarm volume set to max');
    } on PlatformException catch (e) {
      debugPrint('EmergencyVolume: failed to set alarm volume: ${e.message}');
    }
  }

  /// Restores normal media volume.
  static Future<void> deactivate() async {
    try {
      await _channel.invokeMethod('restoreMediaVolume');
      _isActive = false;
      debugPrint('EmergencyVolume: media volume restored');
    } on PlatformException catch (e) {
      debugPrint('EmergencyVolume: failed to restore volume: ${e.message}');
    }
  }
}
