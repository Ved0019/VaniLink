package com.example.itantra

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "vanilink/audio"
    private var savedMediaVolume: Int = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlarmVolume" -> {
                        // Save current media volume for later restoration
                        savedMediaVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_ALARM,
                            maxVol,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "restoreMediaVolume" -> {
                        if (savedMediaVolume >= 0) {
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_MUSIC,
                                savedMediaVolume,
                                0
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
