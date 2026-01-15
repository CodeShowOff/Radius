# Platform Configuration Guide

This guide covers Android and iOS configuration for Radius, including Bluetooth LE permissions, location access, background modes, and battery optimization.

## Prerequisites

Generate platform folders if they don't exist:

```bash
flutter create . --platforms=android,ios
```

---

## Android Configuration

### 1. AndroidManifest.xml

**Location:** `android/app/src/main/AndroidManifest.xml`

Add these permissions and features inside the `<manifest>` tag, before `<application>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- ============================================== -->
    <!-- BLUETOOTH PERMISSIONS -->
    <!-- ============================================== -->
    
    <!-- Bluetooth permissions for Android 12+ (API 31+) -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    
    <!-- Bluetooth permissions for Android 11 and below -->
    <uses-permission android:name="android.permission.BLUETOOTH" 
        android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" 
        android:maxSdkVersion="30" />
    
    <!-- ============================================== -->
    <!-- LOCATION PERMISSIONS -->
    <!-- ============================================== -->
    
    <!-- Required for BLE scanning on Android 11 and below -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    
    <!-- Background location (required for background BLE scanning) -->
    <!-- NOTE: Requires special justification for Play Store -->
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    
    <!-- ============================================== -->
    <!-- BACKGROUND & SERVICE PERMISSIONS -->
    <!-- ============================================== -->
    
    <!-- Keep app running in background -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    
    <!-- Receive boot completed to restart service -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    
    <!-- Prevent Doze mode from stopping BLE scans -->
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    
    <!-- ============================================== -->
    <!-- NETWORK PERMISSIONS -->
    <!-- ============================================== -->
    
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    
    <!-- ============================================== -->
    <!-- HARDWARE FEATURES -->
    <!-- ============================================== -->
    
    <!-- Declare BLE hardware requirement -->
    <uses-feature 
        android:name="android.hardware.bluetooth_le" 
        android:required="true" />
    
    <!-- Location hardware (not strictly required) -->
    <uses-feature 
        android:name="android.hardware.location.gps" 
        android:required="false" />

    <application
        android:label="Radius"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- ============================================== -->
        <!-- FOREGROUND SERVICE DECLARATION -->
        <!-- ============================================== -->
        
        <!-- Required for Android 14+ (API 34+) -->
        <service
            android:name="com.example.radius.ProximityService"
            android:foregroundServiceType="connectedDevice"
            android:exported="false" />
        
        <!-- Boot receiver to restart proximity service -->
        <receiver
            android:name="com.example.radius.BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
        
        <!-- ... rest of application config ... -->
        
    </application>
</manifest>
```

### 2. Build Gradle Configuration

**Location:** `android/app/build.gradle`

```gradle
android {
    compileSdkVersion 34  // Required for latest Bluetooth APIs
    
    defaultConfig {
        minSdkVersion 21   // Minimum for BLE
        targetSdkVersion 34
    }
}
```

### 3. Android Permission Rationale

| Permission | Why Needed | When Requested |
|------------|-----------|----------------|
| `BLUETOOTH_SCAN` | Discover nearby devices | App start |
| `BLUETOOTH_ADVERTISE` | Broadcast presence to others | App start |
| `BLUETOOTH_CONNECT` | Connect to discovered devices | Optional |
| `ACCESS_FINE_LOCATION` | Required for BLE on Android ≤11 | App start |
| `ACCESS_BACKGROUND_LOCATION` | BLE scanning when app backgrounded | After foreground granted |
| `FOREGROUND_SERVICE` | Keep proximity service running | Automatic |

---

## iOS Configuration

### 1. Info.plist

**Location:** `ios/Runner/Info.plist`

Add these entries inside the `<dict>` tag:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ============================================== -->
    <!-- BLUETOOTH PERMISSIONS -->
    <!-- ============================================== -->
    
    <!-- Required: Bluetooth usage description (iOS 13+) -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Radius uses Bluetooth to discover people nearby and enable connections with them.</string>
    
    <!-- Legacy: Bluetooth peripheral usage (iOS 6-12) -->
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Radius uses Bluetooth to discover people nearby and enable connections with them.</string>
    
    <!-- ============================================== -->
    <!-- LOCATION PERMISSIONS -->
    <!-- ============================================== -->
    
    <!-- Location when in use -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Radius uses your location to find people nearby and show them on the map.</string>
    
    <!-- Location always (for background) -->
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>Radius needs background location access to notify you when connections are nearby, even when the app is closed.</string>
    
    <!-- Legacy: Always location (iOS 10 and earlier) -->
    <key>NSLocationAlwaysUsageDescription</key>
    <string>Radius needs background location access to notify you when connections are nearby.</string>
    
    <!-- ============================================== -->
    <!-- BACKGROUND MODES -->
    <!-- ============================================== -->
    
    <key>UIBackgroundModes</key>
    <array>
        <!-- BLE Central (scanning for devices) -->
        <string>bluetooth-central</string>
        
        <!-- BLE Peripheral (advertising as device) -->
        <string>bluetooth-peripheral</string>
        
        <!-- Background fetch for updates -->
        <string>fetch</string>
        
        <!-- Remote notifications -->
        <string>remote-notification</string>
        
        <!-- Background processing (iOS 13+) -->
        <string>processing</string>
    </array>
    
    <!-- ============================================== -->
    <!-- APP TRANSPORT SECURITY -->
    <!-- ============================================== -->
    
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- Allow Firebase and other HTTPS connections -->
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
    
    <!-- ============================================== -->
    <!-- OTHER REQUIRED KEYS -->
    <!-- ============================================== -->
    
    <!-- Camera (if profile photos from camera) -->
    <key>NSCameraUsageDescription</key>
    <string>Radius needs camera access to take profile photos.</string>
    
    <!-- Photo library (if profile photos from gallery) -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Radius needs photo library access to select profile photos.</string>
    
    <!-- ... existing entries ... -->
</dict>
</plist>
```

### 2. Podfile Configuration

**Location:** `ios/Podfile`

```ruby
platform :ios, '13.0'  # Minimum for modern BLE APIs

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    target.build_configurations.each do |config|
      # Required for Bluetooth background modes
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_BLUETOOTH=1',
        'PERMISSION_LOCATION=1',
      ]
    end
  end
end
```

### 3. Entitlements (if using iCloud/Push)

**Location:** `ios/Runner/Runner.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
    
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:radius.app</string>
    </array>
</dict>
</plist>
```

---

## Background Mode Explanation

### Why Background Modes Are Needed

Radius needs to detect nearby users even when the app isn't in the foreground. Without background modes:
- BLE scanning stops when app is backgrounded
- Users won't be notified of nearby connections
- The app loses its core functionality

### How Background BLE Works

#### Android
1. **Foreground Service**: Creates a persistent notification showing "Scanning for nearby users"
2. **Service runs continuously** with wake lock
3. **Doze mode exemption** requested to prevent Android from killing the service

#### iOS
1. **State Restoration**: iOS saves BLE state and restores when app relaunches
2. **Background Execution**: Limited to ~10 seconds after backgrounding, then periodic wake-ups
3. **iBeacon Monitoring**: Can wake app when specific beacon detected (up to 20 regions)

### Background Mode Limitations

| Platform | Limitation | Workaround |
|----------|-----------|------------|
| Android | Doze mode pauses scans | Request battery optimization exemption |
| Android | OEM battery killers | Guide users to disable for app |
| iOS | 10-second background limit | Use state restoration + region monitoring |
| iOS | Throttled when low battery | Accept reduced frequency |
| Both | Battery drain complaints | Implement smart scanning intervals |

---

## Battery Optimization Tips

### 1. Smart Scanning Intervals

```dart
// Don't scan continuously - use intervals
class ProximityConfig {
  // Active scanning (app in foreground)
  static const Duration activeScanDuration = Duration(seconds: 5);
  static const Duration activeScanInterval = Duration(seconds: 10);
  
  // Background scanning (app backgrounded)
  static const Duration backgroundScanDuration = Duration(seconds: 3);
  static const Duration backgroundScanInterval = Duration(seconds: 30);
  
  // Low power mode
  static const Duration lowPowerScanDuration = Duration(seconds: 2);
  static const Duration lowPowerScanInterval = Duration(minutes: 2);
}
```

### 2. Adaptive Scanning

```dart
// Reduce scanning when:
// - No nearby users detected recently
// - User hasn't moved (no location change)
// - Night time / user likely sleeping
// - Battery below 20%

void adjustScanningMode(BatteryState battery, bool hasRecentDetections) {
  if (battery.level < 20) {
    setScanMode(ScanMode.lowPower);
  } else if (!hasRecentDetections) {
    setScanMode(ScanMode.balanced);
  } else {
    setScanMode(ScanMode.active);
  }
}
```

### 3. Batch Operations

```dart
// Don't write to Firestore on every detection
// Batch updates every 30 seconds
class ProximityBatcher {
  final Map<String, DetectedUser> _pendingUpdates = {};
  Timer? _flushTimer;
  
  void addDetection(DetectedUser user) {
    _pendingUpdates[user.id] = user;
    _scheduleFlush();
  }
  
  void _scheduleFlush() {
    _flushTimer ??= Timer(Duration(seconds: 30), _flush);
  }
  
  Future<void> _flush() async {
    if (_pendingUpdates.isEmpty) return;
    
    final batch = FirebaseFirestore.instance.batch();
    for (final user in _pendingUpdates.values) {
      batch.set(docRef(user.id), user.toMap());
    }
    await batch.commit();
    _pendingUpdates.clear();
    _flushTimer = null;
  }
}
```

### 4. User Controls

Provide users control over battery usage:

```dart
enum PowerMode {
  performance,  // Full scanning, highest battery use
  balanced,     // Default, moderate scanning
  batterySaver, // Minimal scanning, lowest battery
}

// Let users choose in settings
class ProximitySettings {
  PowerMode powerMode = PowerMode.balanced;
  bool scanInBackground = true;
  TimeOfDay? quietHoursStart;
  TimeOfDay? quietHoursEnd;
}
```

### 5. Platform-Specific Optimizations

#### Android
```kotlin
// Use low-power scan mode when possible
val scanSettings = ScanSettings.Builder()
    .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER) // vs SCAN_MODE_LOW_LATENCY
    .setReportDelay(5000) // Batch results every 5 seconds
    .build()
```

#### iOS
```swift
// Use opportunistic scanning
centralManager.scanForPeripherals(
    withServices: [serviceUUID],
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
)
```

---

## Platform-Specific Caveats

### Android Caveats

| Issue | Impact | Solution |
|-------|--------|----------|
| **Chinese OEM Battery Killers** | Xiaomi, Huawei, OnePlus aggressively kill background apps | Show user guide to whitelist app |
| **Android 12+ Bluetooth Permissions** | New permission model breaks old code | Request BLUETOOTH_SCAN, not ACCESS_FINE_LOCATION |
| **Doze Mode** | Stops background scanning after ~1 hour idle | Request IGNORE_BATTERY_OPTIMIZATIONS |
| **Background Location Limit** | Play Store requires justification | Document why needed, consider alternatives |
| **Foreground Service Notification** | Required and cannot be hidden | Design informative, non-intrusive notification |

#### Handling OEM Battery Killers

```dart
// Direct users to battery settings
void showBatteryOptimizationGuide(BuildContext context) {
  final deviceBrand = Platform.isAndroid ? getDeviceBrand() : null;
  
  final guides = {
    'xiaomi': 'Settings → Battery → App battery saver → Radius → No restrictions',
    'huawei': 'Settings → Battery → App launch → Radius → Manage manually',
    'samsung': 'Settings → Battery → Background usage limits → Never sleeping apps',
    'oneplus': 'Settings → Battery → Battery optimization → Radius → Don\'t optimize',
  };
  
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Enable Background Running'),
      content: Text(guides[deviceBrand] ?? 'Disable battery optimization for Radius'),
      actions: [
        TextButton(
          onPressed: () => openBatterySettings(),
          child: Text('Open Settings'),
        ),
      ],
    ),
  );
}
```

### iOS Caveats

| Issue | Impact | Solution |
|-------|--------|----------|
| **Background App Refresh** | Must be enabled by user | Check and prompt in settings |
| **Low Power Mode** | Disables background activity | Detect and warn user |
| **App Killed by User** | Background modes don't work | Use push notifications for critical alerts |
| **Privacy Nutrition Labels** | App Store requires disclosure | Document all data collection |
| **Bluetooth Prompt Timing** | Only one chance to explain | Request after onboarding explains why |

#### Checking Background Capabilities

```dart
// Check if background refresh is enabled
Future<bool> checkBackgroundCapabilities() async {
  if (Platform.isIOS) {
    final status = await Permission.backgroundRefresh.status;
    if (status.isDenied) {
      // Show settings prompt
      await openAppSettings();
      return false;
    }
  }
  return true;
}
```

### Both Platforms

| Issue | Impact | Solution |
|-------|--------|----------|
| **First Permission Request** | Users often deny without reading | Show explanation screen BEFORE system prompt |
| **Permission Denied** | Core features don't work | Show clear explanation of impact + settings link |
| **BLE Not Supported** | Old devices can't use app | Check on startup, show graceful error |
| **Bluetooth Disabled** | Can't scan | Monitor state, show enable prompt |

---

## Permission Request Flow

### Recommended Order

```dart
Future<void> requestPermissions() async {
  // 1. Show explanation screen first
  await showPermissionExplanation();
  
  // 2. Request Bluetooth (most important)
  final bluetoothStatus = await Permission.bluetooth.request();
  if (!bluetoothStatus.isGranted) {
    return showBluetoothDeniedScreen();
  }
  
  // 3. Request Bluetooth Scan (Android 12+)
  if (Platform.isAndroid) {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothAdvertise.request();
  }
  
  // 4. Request Location (explain why)
  await showLocationExplanation();
  final locationStatus = await Permission.location.request();
  
  // 5. Request Background Location (Android only, after foreground granted)
  if (Platform.isAndroid && locationStatus.isGranted) {
    await showBackgroundLocationExplanation();
    await Permission.locationAlways.request();
  }
  
  // 6. Request notification permission (Android 13+)
  if (Platform.isAndroid) {
    await Permission.notification.request();
  }
}
```

---

## Testing Checklist

### Android Testing
- [ ] Test on Android 12+ device (new Bluetooth permissions)
- [ ] Test on Android 11 device (location-based BLE)
- [ ] Test background scanning (app minimized for 30+ minutes)
- [ ] Test after device reboot
- [ ] Test with battery saver enabled
- [ ] Test on Xiaomi/Huawei device (aggressive battery management)

### iOS Testing
- [ ] Test on iOS 13+ device
- [ ] Test background scanning (app minimized)
- [ ] Test with Low Power Mode enabled
- [ ] Test after force-quitting app
- [ ] Test Bluetooth permission denial flow
- [ ] Test location permission denial flow

---

## App Store Considerations

### Google Play Store
- **Background location**: Requires policy declaration explaining why needed
- **Bluetooth permissions**: Declare in Data Safety section
- **Foreground service**: Show clear notification explaining what's running

### Apple App Store
- **Privacy Nutrition Labels**: Must declare Bluetooth, location data usage
- **Purpose strings**: Must be clear and specific (rejection risk if vague)
- **Background modes**: Must justify each mode enabled

---

## Quick Reference: Required Permissions

### Android (add to AndroidManifest.xml)
```xml
<!-- Minimum required -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

### iOS (add to Info.plist)
```xml
<!-- Minimum required -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Discover nearby people</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Find people nearby</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
</array>
```
