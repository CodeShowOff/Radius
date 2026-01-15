## iOS Configuration for BLE

### Info.plist Configuration

Add the following to `ios/Runner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing entries... -->
    
    <!-- Bluetooth Usage Descriptions (required) -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Radius uses Bluetooth to discover and connect with nearby users.</string>
    
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Radius uses Bluetooth to let nearby users discover you.</string>
    
    <!-- Background Modes (optional - for future background scanning) -->
    <!-- Uncomment if background BLE is needed -->
    <!--
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-central</string>
        <string>bluetooth-peripheral</string>
    </array>
    -->
    
</dict>
</plist>
```

### Minimum iOS Version

Ensure `ios/Podfile` has:

```ruby
platform :ios, '12.0'
```

### Privacy Descriptions

The usage descriptions are mandatory for App Store submission:

1. **NSBluetoothAlwaysUsageDescription**: Explains why the app needs Bluetooth access
2. **NSBluetoothPeripheralUsageDescription**: Explains why the app acts as a BLE peripheral

### Capabilities

In Xcode, ensure the following capability is enabled:
- **Background Modes** → **Uses Bluetooth LE accessories** (only if background scanning is needed)
