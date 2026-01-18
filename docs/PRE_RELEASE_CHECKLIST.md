# Pre-Release Checklist for Radius App

Use this checklist before building and releasing your app to ensure everything is properly configured.

## ✅ General Configuration

- [ ] Update version in `pubspec.yaml` (format: `1.0.0+1`)
  - First number: major.minor.patch
  - After `+`: build number
  
- [ ] Run `flutter pub get` to ensure all dependencies are installed

- [ ] Run `flutter analyze` to check for code issues

- [ ] Run `flutter test` to ensure all tests pass

- [ ] Generate code with `dart run build_runner build --delete-conflicting-outputs`

## ✅ App Branding

- [ ] App icon created (1024x1024px PNG)
  - File: `assets/icon/app_icon.png`
  - Run: `flutter pub run flutter_launcher_icons`

- [ ] App name is set correctly
  - Android: In `AndroidManifest.xml` (`android:label`)
  - iOS: In `Info.plist` (`CFBundleDisplayName`)

- [ ] Splash screen configured (if needed)

## ✅ Android Configuration

### Application ID
- [ ] Change package name from `com.codeshowoff.radius` to your unique ID
  - File: `android/app/build.gradle.kts`
  - Format: `com.yourcompany.appname`

### Keystore Setup
- [ ] Create keystore file:
  ```bash
  keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```

- [ ] Create `android/key.properties` file (use `key.properties.example` as template)
  - Add keystore password
  - Add key password
  - Add keystore file path

- [ ] Verify `key.properties` is in `.gitignore`

### Firebase
- [ ] Add `google-services.json` to `android/app/`
  - Download from Firebase Console
  - Ensure it's for the correct package name

### Permissions
- [ ] Review permissions in `AndroidManifest.xml`
  - Bluetooth permissions (BLUETOOTH_SCAN, BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT)
  - Internet permission
  - Ensure `neverForLocation` flag is set for BLUETOOTH_SCAN

### Build Configuration
- [ ] ProGuard rules are properly configured (`proguard-rules.pro`)
- [ ] Test release build: `flutter build apk --release`
- [ ] Install and test: `flutter install --release`

## ✅ iOS Configuration

### Bundle Identifier
- [ ] Open project in Xcode: `open ios/Runner.xcworkspace`
- [ ] Change Bundle Identifier from `com.codeshowoff.radius`
  - Location: Runner → Signing & Capabilities
  - Must match your Apple Developer account

### Code Signing
- [ ] Select your Development Team in Xcode
- [ ] Ensure "Automatically manage signing" is checked
- [ ] Verify provisioning profiles are downloaded

### Firebase
- [ ] Add `GoogleService-Info.plist` to `ios/Runner/`
  - Download from Firebase Console
  - Add via Xcode (right-click Runner → Add Files)
  - Ensure "Copy items if needed" is checked

### Permissions
- [ ] Verify Bluetooth permissions in `Info.plist`
  - `NSBluetoothAlwaysUsageDescription` ✓
  - `NSBluetoothPeripheralUsageDescription` ✓

### CocoaPods
- [ ] Run `cd ios && pod install && cd ..`
- [ ] Verify deployment target is iOS 13.0+

### Build Configuration
- [ ] Test on real iOS device (not simulator)
- [ ] Test release build: `flutter build ios --release`

## ✅ Firebase Configuration

- [ ] Firebase project created
- [ ] Android app registered with correct package name
- [ ] iOS app registered with correct Bundle ID
- [ ] Authentication providers enabled (Email, Google)
- [ ] Firestore database created with proper security rules
- [ ] Firebase Analytics enabled
- [ ] Crashlytics enabled
- [ ] Performance Monitoring enabled
- [ ] Remote Config setup (if used)

## ✅ Feature Testing (Release Mode)

Test these features thoroughly in release mode:

- [ ] User authentication (email, Google sign-in)
- [ ] Sign out and sign in again
- [ ] Bluetooth advertising starts on app launch
- [ ] Bluetooth scanning works on Nearby page
- [ ] Users are discovered nearby
- [ ] Connection requests can be sent
- [ ] Connection requests are received (test with 2 devices)
- [ ] Banner notifications appear for new requests
- [ ] Accept/decline connection requests work
- [ ] Chat functionality works between connected users
- [ ] Profile editing and photo upload work
- [ ] All navigation works correctly
- [ ] App doesn't crash on background/foreground transitions
- [ ] Permissions are requested properly
- [ ] Firebase features work (no auth issues)

## ✅ Performance & Optimization

- [ ] App size is reasonable
  - Check APK size: Should be < 50MB
  - Check IPA size: Should be < 100MB

- [ ] App starts quickly (< 3 seconds)

- [ ] No memory leaks (test with long sessions)

- [ ] Battery usage is acceptable

- [ ] Network usage is reasonable

## ✅ App Store Metadata

### Google Play Store
- [ ] App title (30 characters max)
- [ ] Short description (80 characters)
- [ ] Full description (4000 characters)
- [ ] Screenshots (at least 2, up to 8)
  - Phone: 1080x1920 or 1080x2340
  - Tablet: 1536x2048 or 2048x1536
- [ ] Feature graphic (1024x500)
- [ ] App icon (512x512)
- [ ] Privacy policy URL
- [ ] Content rating questionnaire completed
- [ ] Target audience and content

### Apple App Store
- [ ] App name
- [ ] Subtitle (30 characters)
- [ ] Description (4000 characters)
- [ ] Keywords (100 characters, comma-separated)
- [ ] Screenshots
  - 6.5" iPhone: 1284x2778
  - 5.5" iPhone: 1242x2208
  - 12.9" iPad: 2048x2732
- [ ] App Preview video (optional)
- [ ] Privacy policy URL
- [ ] App category
- [ ] Age rating
- [ ] App Store Connect information

## ✅ Legal & Compliance

- [ ] Privacy policy created and hosted
- [ ] Terms of service created (if needed)
- [ ] GDPR compliance (if serving EU users)
- [ ] COPPA compliance (if app is for children)
- [ ] All third-party licenses acknowledged

## ✅ Pre-Submission

- [ ] All sensitive data (API keys, passwords) removed from code
- [ ] Test build on multiple devices
- [ ] Verify app works offline (graceful degradation)
- [ ] Check error messages are user-friendly
- [ ] Verify all text is free of typos
- [ ] Test with poor network conditions
- [ ] Test on different Android versions (if possible)
- [ ] Test on different iOS versions (if possible)

## ✅ Build Commands

### Android
```bash
# APK (direct installation)
flutter build apk --release

# Or use the helper script
build_android_release.bat

# AAB (Google Play Store)
flutter build appbundle --release
```

### iOS
```bash
# iOS build (requires macOS)
flutter build ios --release

# Or use the helper script
./build_ios_release.sh

# IPA (for App Store)
flutter build ipa --release
```

## ✅ Post-Build

- [ ] Install and test release APK on real device
- [ ] Test IPA on real iOS device via Xcode
- [ ] Verify app signing is correct
- [ ] Check app size matches expectations
- [ ] Final functionality test on both platforms

## ✅ Submission

### Google Play Store
- [ ] Upload AAB to Google Play Console
- [ ] Complete store listing
- [ ] Set pricing & distribution
- [ ] Submit for review

### Apple App Store
- [ ] Upload IPA to App Store Connect
- [ ] Complete app information
- [ ] Submit for review
- [ ] Wait for approval (typically 1-3 days)

---

## Common Issues & Fixes

### Android
- **Build fails**: Run `flutter clean && flutter pub get`
- **Signing fails**: Check `key.properties` file path and passwords
- **ProGuard issues**: Check `proguard-rules.pro` has necessary keep rules

### iOS
- **Code signing error**: Verify Apple Developer account in Xcode
- **CocoaPods error**: Run `cd ios && pod deintegrate && pod install`
- **Build error**: Clean Xcode build folder (Cmd+Shift+K)

---

✨ Once all items are checked, you're ready to release!
