# 🚀 Quick Reference - Building Release Versions

## Android Release Build

### First Time Setup
```bash
# 1. Create keystore
keytool -genkey -v -keystore C:/Users/YOUR_USERNAME/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2. Copy and configure key.properties
copy android\key.properties.example android\key.properties
# Edit key.properties with your keystore details

# 3. Change application ID in android/app/build.gradle.kts
# Change: com.codeshowoff.radius → com.yourcompany.radius
```

### Build Commands
```bash
# APK (for testing/direct install)
flutter build apk --release

# AAB (for Google Play Store - recommended)
flutter build appbundle --release

# Or use the helper script
build_android_release.bat
```

### Output Locations
- **APK**: `build\app\outputs\flutter-apk\app-release.apk`
- **AAB**: `build\app\outputs\bundle\release\app-release.aab`

---

## iOS Release Build (macOS only)

### First Time Setup
```bash
# 1. Open in Xcode
open ios/Runner.xcworkspace

# 2. In Xcode → Runner → Signing & Capabilities:
#    - Change Bundle Identifier: com.codeshowoff.radius → com.yourcompany.radius
#    - Select your Team (Apple Developer account)
#    - Let Xcode manage signing automatically

# 3. Update CocoaPods
cd ios
pod install
cd ..
```

### Build Commands
```bash
# iOS build (test on device from Xcode)
flutter build ios --release

# IPA (for App Store/TestFlight)
flutter build ipa --release

# Or use the helper script
chmod +x build_ios_release.sh
./build_ios_release.sh
```

### Output Location
- **IPA**: `build/ios/ipa/radius.ipa`

---

## Before Building - Critical Changes

### ⚠️ Must Do:
1. **Change Application ID**
   - Android: `android/app/build.gradle.kts` → `applicationId`
   - iOS: Xcode → Signing & Capabilities → `Bundle Identifier`

2. **Add App Icon**
   ```bash
   # Place 1024x1024 PNG at: assets/icon/app_icon.png
   flutter pub run flutter_launcher_icons
   ```

3. **Update Version**
   - File: `pubspec.yaml`
   - Format: `version: 1.0.0+1`

4. **Add Firebase Config**
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

---

## Testing Release Builds

```bash
# Run in release mode
flutter run --release

# Install APK on connected device
flutter install --release

# Check for issues
flutter analyze
flutter doctor -v
```

---

## Common Issues & Fixes

### Build Fails
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
# Try build again
```

### Android Signing Error
- Check `android/key.properties` exists
- Verify keystore file path is correct
- Ensure passwords are correct

### iOS Code Signing Error
- Verify Apple Developer account in Xcode
- Check Bundle Identifier matches your account
- Download provisioning profiles

### ProGuard Removes Classes
- Check `android/app/proguard-rules.pro`
- Add keep rules for affected classes

---

## File Checklist

### Android
- [x] `android/app/build.gradle.kts` - Build configuration
- [x] `android/app/proguard-rules.pro` - ProGuard rules
- [ ] `android/key.properties` - Keystore config (create from example)
- [ ] `android/app/google-services.json` - Firebase config
- [ ] `upload-keystore.jks` - Your keystore file

### iOS
- [x] `ios/Podfile` - CocoaPods configuration
- [x] `ios/Runner/Info.plist` - App configuration & permissions
- [ ] `ios/Runner/GoogleService-Info.plist` - Firebase config
- [ ] Bundle Identifier changed in Xcode
- [ ] Signing configured in Xcode

### General
- [ ] `pubspec.yaml` - Version updated
- [ ] `assets/icon/app_icon.png` - App icon added
- [ ] Application ID changed
- [ ] All tests passing

---

## Upload to Stores

### Google Play Store
1. Go to: https://play.google.com/console
2. Create app → Upload AAB
3. Fill store listing
4. Submit for review

### Apple App Store
1. Go to: https://appstoreconnect.apple.com
2. Create app → Upload IPA
3. Fill app information
4. Submit for review

---

## Documentation

- 📖 **RELEASE_GUIDE.md** - Detailed instructions
- ✅ **PRE_RELEASE_CHECKLIST.md** - Complete checklist
- 🎉 **SETUP_COMPLETE.md** - Configuration summary

---

## Need Help?

1. Check `RELEASE_GUIDE.md` for detailed steps
2. Use `PRE_RELEASE_CHECKLIST.md` to verify setup
3. Run `flutter doctor -v` to check your environment
4. Review Flutter docs: https://docs.flutter.dev/deployment

---

**Current Status**: ✅ Ready to build (after completing critical changes above)
