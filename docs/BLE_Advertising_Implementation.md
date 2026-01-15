# BLE Advertising Implementation

## Overview

Native BLE advertising has been implemented for both Android and iOS using platform channels.

## Architecture

```
Flutter (Dart)
    ↓
BleAdvertiser (uses MethodChannel)
    ↓
Platform Channel (com.example.radius/ble_advertiser)
    ↓
Native Code:
  - Android: BleAdvertiserPlugin.kt (BluetoothLeAdvertiser API)
  - iOS: BleAdvertiserPlugin.swift (CBPeripheralManager API)
```

## Files Created

### Android
- **BleAdvertiserPlugin.kt** - Native Android BLE advertising implementation
  - Uses `BluetoothLeAdvertiser` API
  - Broadcasts service UUID + manufacturer data with anonymous ID
  - Low-power advertising mode for battery efficiency

### iOS  
- **BleAdvertiserPlugin.swift** - Native iOS BLE advertising implementation
  - Uses `CBPeripheralManager` from CoreBluetooth
  - Broadcasts service UUID + anonymous ID as local name
  - Handles Bluetooth state changes

### Flutter
- **ble_advertiser.dart** - Updated to use platform channels
  - Communicates with native code via MethodChannel
  - Handles ID rotation and updates
  - Error handling from native callbacks

## How It Works

1. **Initialization**: `BluetoothService` initializes `BleAdvertiser`
2. **Start Advertising**: 
   - Flutter calls native method `startAdvertising` with anonymousId
   - Native code configures and starts BLE advertising
   - Returns success/failure to Flutter
3. **ID Rotation**: 
   - Every 15 minutes, ID generator creates new anonymous ID
   - `_updateAdvertisement()` calls native `updateAdvertisement` method
   - Native code stops and restarts advertising with new ID
4. **Stop Advertising**: Native code stops advertising when requested

## Advertising Data

### Android
```kotlin
AdvertiseData:
  - Service UUID: 00001234-0000-1000-8000-00805f9b34fb
  - Manufacturer Data: 0xFFFF (ID) + anonymousId bytes
  - Mode: LOW_POWER (balanced battery/range)
  - TX Power: MEDIUM
  - Non-connectable
```

### iOS
```swift
Advertisement Data:
  - Service UUIDs: [00001234-0000-1000-8000-00805f9b34fb]
  - Local Name: anonymousId
```

## Testing

### Prerequisites
- Two physical devices (BLE advertising doesn't work on emulators)
- Bluetooth enabled
- Location permissions granted (Android)

### Test Steps

1. **Install on Device 1**
   ```bash
   flutter run
   ```

2. **Sign in and start discovery**
   - Navigate to Nearby Users screen
   - Tap the scan button

3. **Install on Device 2**
   - Repeat steps 1-2

4. **Verify Detection**
   - Both devices should appear in each other's nearby list
   - Distance indicator should update based on RSSI

### Debug Logs

Add this to test advertising status:
```dart
final isAdvertising = await _channel.invokeMethod<bool>('isAdvertising');
print('BLE Advertising: $isAdvertising');
```

## Permissions

### Android (Already Configured)
- `BLUETOOTH_ADVERTISE` (API 31+)
- `BLUETOOTH_SCAN` (API 31+)
- `BLUETOOTH` (API ≤30)
- `BLUETOOTH_ADMIN` (API ≤30)
- `ACCESS_FINE_LOCATION`

### iOS (Already Configured)
- `NSBluetoothAlwaysUsageDescription` in Info.plist
- `NSBluetoothPeripheralUsageDescription` in Info.plist

## Battery Optimization

- **Advertising Mode**: LOW_POWER (Android) / Default (iOS)
- **Advertising Interval**: Automatic (optimized by OS)
- **ID Rotation**: Every 15 minutes (reduces data transmitted)
- **Scan Interval**: 30 seconds (configurable in BleConstants)

## Troubleshooting

### Advertising Doesn't Start
1. Check Bluetooth is enabled
2. Verify permissions granted
3. Check logcat/Xcode console for errors
4. Ensure device supports BLE peripheral mode (most modern phones do)

### Devices Not Discovering Each Other
1. Ensure both devices are advertising AND scanning
2. Check they're using same service UUID
3. Verify Bluetooth range (within ~10 meters)
4. Check RSSI threshold in BleConstants

### High Battery Drain
1. Increase scan interval in `BleConstants.scanIntervalSeconds`
2. Reduce scan duration in `BleConstants.scanDurationSeconds`
3. Use battery saver mode (already implemented in BleScanner)

## Production Considerations

1. **Company ID**: Change `MANUFACTURER_ID` from 0xFFFF to your registered Bluetooth SIG ID
2. **Service UUID**: Keep unique UUID or register an official one
3. **Background Modes**: 
   - Android: Foreground service needed for background advertising
   - iOS: Already configured in Info.plist (optional)
4. **Privacy**: Anonymous IDs rotate every 15 minutes
5. **Rate Limiting**: Firestore security rules prevent spam

## Next Steps

✅ BLE advertising is now fully implemented!

To test proximity detection end-to-end:
1. Complete Firebase setup (`flutterfire configure`)
2. Deploy Firestore security rules
3. Build and install on 2+ physical devices
4. Sign in on each device
5. Navigate to "Nearby" screen
6. Watch users appear as they come within range!
