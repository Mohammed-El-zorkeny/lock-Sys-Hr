package com.example.locksys_hr

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.locksys_hr/device_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isDeveloperOptionsEnabled") {
                val enabled = isDeveloperOptionsEnabled()
                result.success(enabled)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun isDeveloperOptionsEnabled(): Boolean {
        return try {
            val devOptions = Settings.Global.getInt(
                contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0
            )
            devOptions != 0
        } catch (e: Exception) {
            false
        }
    }
}
