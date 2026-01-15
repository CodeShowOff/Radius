## Android Configuration for BLE

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Bluetooth permissions -->
    <!-- For Android 12 (API 31) and above -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    
    <!-- For Android 11 (API 30) and below -->
    <uses-permission android:name="android.permission.BLUETOOTH" 
        android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" 
        android:maxSdkVersion="30" />
    
    <!-- Location permission (required for BLE scanning on Android) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    
    <!-- Declare BLE feature -->
    <uses-feature android:name="android.hardware.bluetooth_le" 
        android:required="true" />
    
    <application
        ...
    </application>
</manifest>
```

### ProGuard Rules (if using code obfuscation)

Add to `android/app/proguard-rules.pro`:

```proguard
-keep class com.google.protobuf.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
```

### Minimum SDK Version

Ensure `android/app/build.gradle` has:

```gradle
android {
    defaultConfig {
        minSdkVersion 21  // Minimum for BLE
        targetSdkVersion 34
    }
}
```
