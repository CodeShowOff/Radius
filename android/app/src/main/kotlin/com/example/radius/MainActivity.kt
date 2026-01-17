package com.example.radius

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Foreground-only BLE: only the advertiser plugin is registered.
        // Register BLE Advertiser Plugin
        flutterEngine.plugins.add(BleAdvertiserPlugin())
    }
}
