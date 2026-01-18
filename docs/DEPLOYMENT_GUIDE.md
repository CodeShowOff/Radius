# Quick Deployment Guide

## Step 1: Install Dependencies
```bash
flutter pub get
```

## Step 2: Generate Dependency Injection
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Step 3: Deploy Firebase Rules

### Deploy Firestore Rules
```bash
firebase deploy --only firestore:rules
```

### Deploy Storage Rules
```bash
firebase deploy --only storage
```

### Or Deploy Both
```bash
firebase deploy --only firestore:rules,storage
```

## Step 4: Update Android Permissions

Add to `android/app/src/main/AndroidManifest.xml` before `</manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

## Step 5: Update iOS Permissions

Add to `ios/Runner/Info.plist` before `</dict>`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to take photos for messages</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is needed to send images</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is needed to record voice messages</string>
```

## Step 6: Test the App
```bash
flutter run
```

## Verification Checklist

- [ ] Dependencies installed successfully
- [ ] Build runner generated injection code
- [ ] Firebase rules deployed
- [ ] Android permissions added
- [ ] iOS permissions added
- [ ] App builds without errors
- [ ] Can send text messages
- [ ] Can send images from gallery
- [ ] Can take photos with camera
- [ ] Can record voice messages
- [ ] Can send documents
- [ ] Media displays correctly in chat

## Troubleshooting

### "Permission denied" when uploading
- Deploy Firebase Storage rules: `firebase deploy --only storage`

### "Module not found" errors
- Run: `flutter pub get`
- Run: `flutter pub run build_runner build --delete-conflicting-outputs`

### "Permission denied" on device
- Check Android/iOS permissions are added
- Restart the app completely
- On Android: Go to Settings → Apps → Radius → Permissions → Allow

### Firebase quota exceeded
- Check Firebase Console → Usage tab
- Free tier should be sufficient for testing
- Consider upgrading if needed for production

## What's Next?

All WhatsApp-like chat features are now ready:
✅ Text messages
✅ Images (camera & gallery)
✅ Voice messages
✅ Documents
✅ Stickers support

The app uses:
- **Firestore** for message metadata (free: 1GB storage)
- **Firebase Storage** for media files (free: 5GB storage)

Both are more than enough for development and testing!
