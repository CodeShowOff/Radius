# Building Radius App for Release

This guide will help you build production-ready APK/AAB for Android and IPA for iOS.

## Prerequisites

### General
- Flutter SDK installed and up to date (`flutter upgrade`)
- All dependencies installed (`flutter pub get`)
- Valid Firebase configuration files (google-services.json for Android, GoogleService-Info.plist for iOS)

### Android
- Android SDK installed
- JDK 17 or higher
- For Google Play Store: Create keystore for app signing

### iOS (macOS only)
- Xcode 14+ installed
- Apple Developer account (for TestFlight/App Store)
- Valid provisioning profile and signing certificate
- CocoaPods installed (`sudo gem install cocoapods`)

---

## Android Release Build

### Step 1: Create Keystore (First Time Only)

Create a keystore file for signing your app:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

You'll be prompted to enter:
- Keystore password (remember this!)
- Key password (remember this!)
- Your name, organization, location, etc.

### Step 2: Configure Signing

Create `android/key.properties` file:

```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=upload
storeFile=C:/Users/YourUsername/upload-keystore.jks
```

**Important:** Add `android/key.properties` to `.gitignore` (already done)

### Step 3: Update Build Configuration

The build.gradle.kts is already configured. Just ensure:
- Application ID is unique: Currently `com.example.radius` (change to your domain)
- Version is correct in pubspec.yaml

### Step 4: Build Release APK or AAB

**For APK (direct installation):**
```bash
flutter build apk --release
```

**For AAB (Google Play Store - recommended):**
```bash
flutter build appbundle --release
```

**Output locations:**
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

### Step 5: Test Release Build

```bash
flutter install --release
```

---

## iOS Release Build

### Step 1: Update Bundle Identifier

1. Open the project in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. In Xcode:
   - Select "Runner" in the project navigator
   - Go to "Signing & Capabilities" tab
   - Change Bundle Identifier from `com.example.radius` to your unique identifier (e.g., `com.yourcompany.radius`)
   - Select your Team (Apple Developer account)
   - Xcode will automatically create/download provisioning profiles

### Step 2: Update Info.plist (Already Configured)

The Info.plist already has required permissions for:
- Bluetooth (BLE scanning/advertising)
- All usage descriptions are properly set

### Step 3: Update CocoaPods

```bash
cd ios
pod install
pod update
cd ..
```

### Step 4: Build Release IPA

**For testing on device:**
```bash
flutter build ios --release
```

Then open in Xcode and run on device.

**For TestFlight/App Store:**
```bash
flutter build ipa --release
```

Output: `build/ios/ipa/radius.ipa`

### Step 5: Upload to App Store Connect

1. Use Xcode Organizer:
   - Open Xcode
   - Window → Organizer
   - Select your archive
   - Click "Distribute App"
   - Follow the wizard for TestFlight or App Store

2. Or use Transporter app:
   - Download Apple Transporter from App Store
   - Drag and drop the .ipa file
   - Upload to App Store Connect

---

## Important Configuration Updates Needed

### 1. Change Application ID (Required)

**Android:** Edit `android/app/build.gradle.kts`:
```kotlin
applicationId = "com.yourcompany.radius"  // Change this
```

**iOS:** Edit in Xcode (Signing & Capabilities)

### 2. Add App Icon

The launcher icon configuration is already set in pubspec.yaml. Just ensure you have:
- `assets/icon/app_icon.png` (at least 1024x1024px)

Generate icons:
```bash
flutter pub run flutter_launcher_icons
```

### 3. Verify Firebase Configuration

Ensure you have:
- `android/app/google-services.json` (from Firebase Console)
- `ios/Runner/GoogleService-Info.plist` (from Firebase Console)

---

## Common Issues & Solutions

### Android

**Issue:** Build fails with "Duplicate class" error
**Solution:** Clean build and rebuild:
```bash
flutter clean
flutter pub get
flutter build apk --release
```

**Issue:** ProGuard removes necessary classes
**Solution:** The `proguard-rules.pro` is already configured with necessary keep rules

### iOS

**Issue:** "No valid code signing certificate" error
**Solution:** 
- Ensure you're logged into Xcode with Apple Developer account
- Download certificates and profiles from Apple Developer portal
- In Xcode: Preferences → Accounts → Download Manual Profiles

**Issue:** CocoaPods installation fails
**Solution:**
```bash
cd ios
pod repo update
pod deintegrate
pod install
cd ..
```

**Issue:** Bluetooth permissions not working
**Solution:** The Info.plist already has correct permissions. Ensure iOS 13.0+ deployment target (already set)

---

## Build Size Optimization

The app is already configured with:
- Code obfuscation (minifyEnabled)
- Resource shrinking (shrinkResources)
- ProGuard optimization

For further optimization:
```bash
# Android - split APKs per architecture
flutter build apk --release --split-per-abi

# This creates separate APKs for arm64-v8a, armeabi-v7a, x86_64
```

---

## Release Checklist

### Before Release
- [ ] Update version in `pubspec.yaml` (e.g., `1.0.0+1`)
- [ ] Change application ID from `com.example.radius`
- [ ] Add proper app icon (1024x1024px)
- [ ] Test release build thoroughly on real devices
- [ ] Verify all Firebase features work in release mode
- [ ] Verify Bluetooth discovery works in release mode
- [ ] Check all permissions are requested properly
- [ ] Review and update privacy policy URLs
- [ ] Update app store descriptions and screenshots

### Android Specific
- [ ] Create and configure keystore
- [ ] Update `key.properties` with keystore info
- [ ] Build and test AAB/APK
- [ ] Verify ProGuard doesn't break functionality

### iOS Specific
- [ ] Update Bundle Identifier in Xcode
- [ ] Configure signing with valid certificate
- [ ] Test on actual iOS device (not just simulator)
- [ ] Prepare app store screenshots and metadata
- [ ] Submit for App Store review

---

## Useful Commands

```bash
# Check Flutter and dependencies
flutter doctor -v

# Clean project
flutter clean

# Get dependencies
flutter pub get

# Run in release mode (for testing)
flutter run --release

# Build commands
flutter build apk --release                    # Android APK
flutter build appbundle --release              # Android AAB
flutter build ios --release                    # iOS build
flutter build ipa --release                    # iOS IPA

# Analyze code
flutter analyze

# Run tests
flutter test
```

---

## App Store Submission

### Google Play Store (Android)
1. Create app in Google Play Console
2. Upload AAB file
3. Fill in store listing, screenshots, privacy policy
4. Set up content rating
5. Submit for review

### Apple App Store (iOS)
1. Create app in App Store Connect
2. Upload IPA via Xcode Organizer or Transporter
3. Fill in app information, screenshots, privacy details
4. Submit for review (usually takes 1-3 days)

---

## Support & Troubleshooting

If you encounter issues:
1. Run `flutter doctor -v` to check your setup
2. Clean and rebuild: `flutter clean && flutter pub get`
3. Check Flutter release notes for known issues
4. For iOS: Clean Xcode build folder (Cmd+Shift+K)
5. For Android: Invalidate caches in Android Studio

For platform-specific issues:
- Android: Check logcat (`adb logcat`)
- iOS: Check device logs in Xcode (Window → Devices and Simulators)
