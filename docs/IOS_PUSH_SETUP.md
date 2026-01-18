# iOS Push Notification Setup - Manual Steps

## ✅ Completed Automatically

1. ✅ Added `FirebaseAppDelegateProxyEnabled` to Info.plist
2. ✅ Updated AppDelegate.swift with Firebase/FCM configuration
3. ✅ Added remote notification registration
4. ✅ Configured APNS token handling

## ⚠️ Manual Steps Required in Xcode

These capabilities **must be enabled manually** in Xcode:

### 1. Open Xcode Project
```bash
open ios/Runner.xcworkspace
```

### 2. Enable Capabilities

1. Select **Runner** target in Xcode
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability** button

#### Add: Push Notifications
- Click **+ Capability**
- Search for "Push Notifications"
- Add it

#### Add: Background Modes
- Click **+ Capability**
- Search for "Background Modes"
- Add it
- Check ✅ **Remote notifications**

### 3. Apple Developer Account Setup

For push notifications to work on real devices, you need:

1. **Apple Developer Account** (paid)
2. **APNs Certificate/Key** configured in Apple Developer Portal
3. Upload APNs key to Firebase Console:
   - Go to Firebase Console → Project Settings → Cloud Messaging
   - Under iOS app, upload your APNs Authentication Key

---

## Code Changes Made

### Info.plist
Added Firebase configuration:
```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

### AppDelegate.swift
Added imports and configuration:
```swift
import Firebase
import FirebaseMessaging

FirebaseApp.configure()
UNUserNotificationCenter.current().delegate = self
application.registerForRemoteNotifications()
Messaging.messaging().apnsToken = deviceToken
```

---

## Testing

1. **Simulator:** Push notifications won't work (APNs requires real device)
2. **Real Device:** Requires proper provisioning profile with Push Notifications entitlement

---

## Current Status

✅ Code configuration complete
⏳ Xcode capabilities need manual setup
⏳ APNs certificate needs upload to Firebase
