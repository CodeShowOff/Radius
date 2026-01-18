# Radius App - Release Build Setup Complete! 🎉

Your app is now configured and ready for release builds on both Android and iOS.

## 📋 What Has Been Configured

### ✅ Android
- **Build configuration**: Updated `build.gradle.kts` with proper signing support
- **ProGuard rules**: Already configured for code obfuscation and optimization
- **Keystore setup**: Template created (`key.properties.example`)
- **Release script**: `build_android_release.bat` for easy building

### ✅ iOS
- **Info.plist**: Bluetooth permissions properly configured
- **Podfile**: iOS 13.0+ deployment target set
- **Release script**: `build_ios_release.sh` for easy building

### ✅ Documentation
- **RELEASE_GUIDE.md**: Complete step-by-step guide for building releases
- **PRE_RELEASE_CHECKLIST.md**: Comprehensive checklist before releasing
- **key.properties.example**: Template for Android keystore configuration

## 🚀 Quick Start Guide

### For Android (Windows/Mac/Linux)

1. **Create keystore** (first time only):
   ```bash
   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. **Configure signing**:
   - Copy `android/key.properties.example` to `android/key.properties`
   - Edit with your keystore details

3. **Build release**:
   ```bash
   # Using the helper script (Windows)
   build_android_release.bat
   
   # Or manually
   flutter build appbundle --release  # For Play Store
   flutter build apk --release         # For direct installation
   ```

### For iOS (Mac only)

1. **Open in Xcode**:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Configure signing**:
   - Select Runner → Signing & Capabilities
   - Change Bundle Identifier from `com.example.radius`
   - Select your Team (Apple Developer account)

3. **Build release**:
   ```bash
   # Using the helper script
   chmod +x build_ios_release.sh
   ./build_ios_release.sh
   
   # Or manually
   flutter build ipa --release  # For App Store
   ```

## ⚠️ Important: Before Building

### Must Change:
1. **Application ID** (Android): In `android/app/build.gradle.kts`
   - Current: `com.example.radius`
   - Change to: `com.yourcompany.radius`

2. **Bundle Identifier** (iOS): In Xcode Signing & Capabilities
   - Current: `com.example.radius`
   - Change to: `com.yourcompany.radius`

### Must Add:
1. **App Icon**: Place 1024x1024 PNG at `assets/icon/app_icon.png`
   - Then run: `flutter pub run flutter_launcher_icons`

2. **Firebase Config**:
   - Android: `google-services.json` in `android/app/`
   - iOS: `GoogleService-Info.plist` in `ios/Runner/`

3. **Version Number**: Update in `pubspec.yaml`
   - Current: `1.0.0+1`
   - Format: `major.minor.patch+buildNumber`

## 📱 Testing Release Builds

### Android
```bash
# Build and install
flutter build apk --release
flutter install --release

# Or just run in release mode
flutter run --release
```

### iOS
```bash
# Run in release mode
flutter run --release

# Or build and test from Xcode
flutter build ios --release
# Then open ios/Runner.xcworkspace and run on device
```

## 🔍 Current Status

✅ **Flutter**: Version 3.38.7 (stable)
✅ **Android SDK**: Version 36.1.0
✅ **Code Analysis**: No issues found
✅ **Build Configuration**: Ready
✅ **Signing Setup**: Configured (needs your keystore)

⚠️ **iOS Building**: Requires macOS (you're on Windows)
   - For iOS builds, use a Mac or cloud build service

## 📝 Next Steps

1. **Review PRE_RELEASE_CHECKLIST.md** - Complete all items
2. **Change application IDs** - Use your own domain
3. **Add app icon** - 1024x1024px PNG
4. **Configure Firebase** - Add config files
5. **Create keystore** - For Android signing
6. **Test thoroughly** - Use release builds on real devices
7. **Follow RELEASE_GUIDE.md** - For detailed instructions

## 🛠️ Build Commands Reference

```bash
# Clean project
flutter clean

# Get dependencies
flutter pub get

# Generate code
dart run build_runner build --delete-conflicting-outputs

# Android builds
flutter build apk --release           # APK
flutter build appbundle --release     # AAB (Play Store)
flutter build apk --split-per-abi     # Split APKs (smaller size)

# iOS builds (Mac only)
flutter build ios --release           # iOS build
flutter build ipa --release           # IPA (App Store)

# Test release mode
flutter run --release
```

## 📚 Documentation Files

- **RELEASE_GUIDE.md** - Complete release build guide
- **PRE_RELEASE_CHECKLIST.md** - Pre-release checklist
- **android/key.properties.example** - Keystore configuration template

## ⚡ Quick Build Scripts

### Windows
- `build_android_release.bat` - Interactive Android build script

### Mac/Linux
- `build_ios_release.sh` - Interactive iOS build script

## 🔒 Security Notes

The following files are **excluded from git** (sensitive):
- `*.jks` / `*.keystore` - Keystore files
- `android/key.properties` - Keystore passwords
- `google-services.json` - Firebase config (Android)
- `GoogleService-Info.plist` - Firebase config (iOS)

**Never commit these files to version control!**

## 🐛 Troubleshooting

If builds fail:

1. **Clean and rebuild**:
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

2. **Check Flutter setup**:
   ```bash
   flutter doctor -v
   ```

3. **Android issues**: Check `proguard-rules.pro` is correct

4. **iOS issues** (Mac):
   ```bash
   cd ios
   pod deintegrate
   pod install
   cd ..
   ```

## 📞 Need Help?

- Check **RELEASE_GUIDE.md** for detailed instructions
- Use **PRE_RELEASE_CHECKLIST.md** to ensure nothing is missed
- Review Flutter documentation: https://docs.flutter.dev/deployment
- Check platform-specific guides:
  - Android: https://docs.flutter.dev/deployment/android
  - iOS: https://docs.flutter.dev/deployment/ios

---

## ✨ Summary

Your Radius app is **fully configured** and **ready for release builds**! 

**To build for Android right now:**
1. Change application ID in `android/app/build.gradle.kts`
2. Create keystore and configure `key.properties`
3. Run `build_android_release.bat`

**For iOS builds:**
- You'll need a Mac (currently on Windows)
- Or use a cloud build service like Codemagic or Bitrise

Good luck with your release! 🚀
