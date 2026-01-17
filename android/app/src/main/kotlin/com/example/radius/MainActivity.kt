package com.example.radius

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register BLE Advertiser Plugin
        flutterEngine.plugins.add(BleAdvertiserPlugin())

        // Register BLE Background Scan Plugin (PendingIntent + opt-in FGS).
        flutterEngine.plugins.add(BleBackgroundScanPlugin())
    }
}
