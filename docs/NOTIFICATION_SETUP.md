# Push Notifications Setup Guide

## ✅ Implementation Complete

Your app now has **WhatsApp-style push notifications** with:

### 1. **System Notifications** 📱
- Appear in device notification panel (Android/iOS)
- Show when app is open, background, or closed
- Live badge counts on chat conversations
- Notification sound and vibration

### 2. **Features Implemented**
✅ Firebase Cloud Messaging (FCM) integration  
✅ Foreground notification display  
✅ Background notification handling  
✅ In-app banner for connection requests (5-second auto-dismiss)  
✅ Badge count on Connections button (live updates)  
✅ Unread message badges on conversation tiles  
✅ Cloud Functions to trigger notifications  
✅ Multi-device token management  

---

## 📋 Setup Instructions

### Step 1: Install Node.js Dependencies (Cloud Functions)

```powershell
cd functions
npm install
```

### Step 2: Deploy Cloud Functions

```powershell
# From functions directory
npm run deploy

# Or from project root
firebase deploy --only functions
```

This deploys two functions:
- `onMessageSent` - Sends notifications when messages arrive
- `onConnectionRequestReceived` - Sends notifications for connection requests

### Step 3: Configure Android

The AndroidManifest.xml has been updated with:
- `POST_NOTIFICATIONS` permission (Android 13+)
- Notification channel configuration is in `NotificationService`

**No additional Android setup needed!**

### Step 4: Configure iOS (if building for iOS)

Add to `ios/Runner/Info.plist`:

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

And update `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import Firebase
import FirebaseMessaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
  }
}
```

Add capabilities in Xcode:
- Push Notifications
- Background Modes → Remote notifications

---

## 🎯 How It Works

### When User Sends Message:

1. **Message created in Firestore** → `conversations/{id}/messages/{messageId}`
2. **Cloud Function triggered** → `onMessageSent`
3. **Function fetches recipient's FCM tokens** from Firestore
4. **Notification sent to all devices** via Firebase Messaging
5. **Recipient sees notification** in system panel
6. **Tapping opens chat** with that conversation

### When Connection Request Sent:

1. **Request created** → `connection_requests/{requestId}`
2. **Cloud Function triggered** → `onConnectionRequestReceived`
3. **Notification sent** to recipient's devices
4. **In-app banner shows** if app is open (5 seconds)
5. **Badge count updates** on Connections button
6. **System notification** shows in panel if app is closed

### FCM Token Management:

- **Tokens saved** to Firestore at `users/{userId}/fcmTokens/{token}`
- **Auto-updates** when token refreshes
- **Multi-device support** - user can get notifications on all devices
- **Invalid tokens removed** automatically by Cloud Functions

---

## 🔍 Testing Notifications

### Test in Development:

1. **Run the app** on a physical device (emulator may not get FCM)
2. **Sign in with two accounts** (two devices or web + device)
3. **Send a message** from one account
4. **Check notification** appears on the other device

### Check FCM Token Registration:

1. Open Firebase Console → Firestore
2. Go to `users/{userId}`
3. Check `fcmTokens` field - should contain device tokens

### Test Cloud Functions:

```powershell
# View function logs
firebase functions:log

# Test locally with emulator
npm run serve
```

---

## 📊 Notification Flow Diagram

```
┌─────────────┐
│   Message   │
│   Sent      │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────┐
│  Firestore Trigger          │
│  onMessageSent()            │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│  Fetch Recipient FCM Tokens │
│  from users/{id}/fcmTokens  │
└──────┬──────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│  Send via FCM               │
│  admin.messaging().send()   │
└──────┬──────────────────────┘
       │
       ├─────────────┬─────────────┐
       ▼             ▼             ▼
   ┌────────┐   ┌────────┐   ┌────────┐
   │Device 1│   │Device 2│   │Device 3│
   │ 🔔     │   │ 🔔     │   │ 🔔     │
   └────────┘   └────────┘   └────────┘
```

---

## 🎨 UI Features

### 1. **In-App Banner** (Connection Requests)
- Shows at top of screen for 5 seconds
- Accept/Decline/Dismiss buttons
- Displays sender's photo and name

### 2. **Badge Counts**
- **Connections button** - Shows pending request count
- **Conversation tiles** - Shows unread message count (up to 99+)
- **Connection Requests tabs** - Shows received/sent counts

### 3. **System Notifications**
- **Title**: Sender name
- **Body**: Message text or "New Connection Request"
- **Icon**: App icon
- **Sound**: Default notification sound
- **Tap action**: Opens relevant screen

---

## 🔧 Customization

### Change Notification Sound:

Edit `notification_service.dart`:

```dart
android: AndroidNotificationDetails(
  'radius_messages',
  'Messages',
  sound: RawResourceAndroidNotificationSound('custom_sound'),  // Add custom sound
),
```

### Change Notification Icon:

Place icon in `android/app/src/main/res/drawable/notification_icon.png`

Update:
```dart
icon: 'notification_icon',  // Custom icon name
```

### Modify Notification Channel:

```dart
const androidChannel = AndroidNotificationChannel(
  'radius_messages',  // Change ID
  'Messages',  // Change name
  importance: Importance.max,  // Change priority
);
```

---

## 🐛 Troubleshooting

### Notifications Not Received?

1. **Check FCM token saved**:
   - Firestore → `users/{userId}/fcmTokens`
   - Should contain at least one token

2. **Check Cloud Functions deployed**:
   ```powershell
   firebase functions:list
   ```

3. **Check function logs**:
   ```powershell
   firebase functions:log
   ```

4. **Verify permissions granted**:
   - Android: Settings → Apps → Radius → Notifications → Enabled
   - iOS: Settings → Radius → Notifications → Allow Notifications

### Token Not Saving?

- Check Firestore rules allow write to `users/{userId}`
- Check device has internet connection
- Check Firebase project ID matches in google-services.json

### Functions Not Triggering?

- Verify functions are deployed: `firebase deploy --only functions`
- Check Firestore security rules don't block reads
- View logs: `firebase functions:log`

---

## 📦 Dependencies Added

```yaml
firebase_messaging: ^15.1.6
flutter_local_notifications: ^18.0.1
```

Cloud Functions:
```json
"firebase-admin": "^12.0.0",
"firebase-functions": "^5.0.0"
```

---

## 🚀 Next Steps

1. **Deploy functions**: `cd functions && npm run deploy`
2. **Test on real device**: Build and install APK
3. **Monitor function logs**: `firebase functions:log --follow`
4. **Add custom sounds/icons**: Optional customization

---

## 📱 Production Checklist

- [ ] Cloud Functions deployed to Firebase
- [ ] FCM tokens saving to Firestore
- [ ] Notifications showing on Android
- [ ] Notifications showing on iOS (if applicable)
- [ ] Badge counts updating correctly
- [ ] Invalid tokens being cleaned up
- [ ] Function logs show no errors
- [ ] Test with multiple devices
- [ ] Test background/foreground/closed states

---

**Your app now has professional-grade push notifications like WhatsApp!** 🎉
