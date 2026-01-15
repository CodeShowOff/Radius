# Production Release Guide

Complete guide for releasing Radius to the App Store and Google Play Store.

---

## Pre-Release Checklist

### Code Quality
- [ ] All features tested on real devices (Android + iOS)
- [ ] No debug prints or console.log statements
- [ ] All TODO comments resolved or tracked
- [ ] Code reviewed and approved
- [ ] Unit tests passing (minimum 70% coverage)
- [ ] Integration tests passing
- [ ] No hardcoded API keys or secrets
- [ ] ProGuard/R8 rules configured (Android)
- [ ] App size optimized (< 100MB recommended)

### Security
- [ ] Firebase security rules deployed and tested
- [ ] API keys restricted by platform/bundle ID
- [ ] SSL certificate pinning enabled
- [ ] No sensitive data in logs
- [ ] Secure storage for tokens (Keychain/Keystore)
- [ ] Input validation on all user inputs
- [ ] Rate limiting implemented

### Performance
- [ ] App startup time < 3 seconds
- [ ] No memory leaks (profile with DevTools)
- [ ] Battery usage acceptable
- [ ] Network requests optimized
- [ ] Images compressed and cached
- [ ] Firestore indexes created

### Legal & Compliance
- [ ] Privacy Policy URL accessible
- [ ] Terms of Service URL accessible
- [ ] GDPR compliance (EU users)
- [ ] CCPA compliance (California users)
- [ ] Age-gating if required (13+ for social apps)
- [ ] Data deletion mechanism implemented
- [ ] Export user data capability (GDPR)

### App Store Assets
- [ ] App icon (all required sizes)
- [ ] Screenshots (iPhone, iPad, Android phone/tablet)
- [ ] Feature graphic (Play Store)
- [ ] App preview video (optional but recommended)
- [ ] Promotional text
- [ ] App description (localized if needed)
- [ ] Keywords/tags optimized
- [ ] Category selected correctly

### Configuration
- [ ] Bundle ID / Package name finalized
- [ ] Version number set correctly
- [ ] Build number incremented
- [ ] Release signing configured
- [ ] Firebase production project configured
- [ ] Analytics enabled
- [ ] Crash reporting enabled

---

## App Store Specific Requirements

### Apple App Store

#### Required Info.plist Keys (with descriptions)
```xml
<!-- Bluetooth - REQUIRED for Radius -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Radius uses Bluetooth to discover people nearby who are also using the app, enabling you to connect and chat with them.</string>

<!-- Location - REQUIRED -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Radius uses your location to show you people nearby and help you discover new connections in your area.</string>

<!-- Background Location - if used -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Radius uses your location in the background to notify you when your connections are nearby, even when you're not actively using the app.</string>

<!-- Camera - if profile photos from camera -->
<key>NSCameraUsageDescription</key>
<string>Radius needs camera access so you can take photos for your profile.</string>

<!-- Photo Library - if profile photos from gallery -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Radius needs access to your photo library so you can choose a profile picture.</string>

<!-- Contacts - if contact sync feature -->
<key>NSContactsUsageDescription</key>
<string>Radius can check if any of your contacts are already using the app to help you connect with them.</string>
```

#### App Store Connect Checklist
- [ ] App Information complete
- [ ] Pricing and Availability set
- [ ] App Privacy questionnaire completed
- [ ] Age Rating questionnaire completed
- [ ] App Review Information provided
- [ ] Version Information complete
- [ ] Build uploaded via Xcode/Transporter
- [ ] Screenshots for all device sizes
- [ ] App Preview videos (optional)

#### Privacy Nutrition Labels
You must declare data collection for:
| Data Type | Collected | Linked to User | Used for Tracking |
|-----------|-----------|----------------|-------------------|
| Contact Info (Email) | Yes | Yes | No |
| Location (Precise) | Yes | Yes | No |
| Location (Coarse) | Yes | Yes | No |
| Identifiers (User ID) | Yes | Yes | No |
| Usage Data | Yes | Yes | No |
| Diagnostics (Crash) | Yes | No | No |

### Google Play Store

#### Required Permissions Declarations
In Play Console, declare why you need:
- **Location**: "Used to discover nearby users for social connections"
- **Bluetooth**: "Used for proximity detection via Bluetooth LE"
- **Background Location** (if used): Requires additional justification form

#### Data Safety Section
| Data Type | Collected | Shared | Purpose |
|-----------|-----------|--------|---------|
| Email | Yes | No | Account |
| Name | Yes | Yes (with connections) | Social |
| Location | Yes | No | App functionality |
| Device IDs | Yes | No | Analytics |

#### Play Store Listing
- [ ] Short description (80 chars max)
- [ ] Full description (4000 chars max)
- [ ] Screenshots (min 2, max 8 per device type)
- [ ] Feature graphic (1024x500)
- [ ] Hi-res icon (512x512)
- [ ] Content rating questionnaire
- [ ] Target audience and content
- [ ] News apps declaration (if applicable)
- [ ] COVID-19 apps declaration (if applicable)

---

## Common Rejection Reasons

### Apple App Store Rejections

#### 1. Guideline 2.1 - App Completeness
**Reason**: Crashes, bugs, placeholder content
**Solution**:
- Test thoroughly on all supported devices
- Remove all placeholder text/images
- Handle all error states gracefully

#### 2. Guideline 4.2 - Minimum Functionality
**Reason**: App doesn't provide enough value
**Solution**:
- Ensure core features work completely
- Don't submit MVP with missing features advertised
- Provide clear onboarding explaining value

#### 3. Guideline 5.1.1 - Data Collection and Storage
**Reason**: Collecting data without disclosure
**Solution**:
- Complete Privacy Nutrition Labels accurately
- Have accessible Privacy Policy
- Request only necessary permissions

#### 4. Guideline 5.1.2 - Data Use and Sharing
**Reason**: Sharing data without consent
**Solution**:
- Get explicit consent before sharing
- Explain what data is shared and why
- Provide opt-out options

#### 5. Guideline 4.3 - Spam
**Reason**: App too similar to existing apps
**Solution**:
- Highlight unique features
- Provide differentiated experience
- Don't copy competitors directly

#### 6. Guideline 2.3 - Accurate Metadata
**Reason**: Screenshots/description don't match app
**Solution**:
- Use real screenshots from the app
- Description must match functionality
- Don't over-promise features

### Google Play Rejections

#### 1. Deceptive Behavior
**Reason**: App does something unexpected
**Solution**:
- Be transparent about functionality
- Don't request unnecessary permissions
- Clearly explain what data is collected

#### 2. User Data Policy Violation
**Reason**: Missing/inadequate privacy policy
**Solution**:
- Privacy Policy must be accessible
- Must cover all data collected
- Must explain third-party sharing

#### 3. Background Location
**Reason**: Using location when not needed
**Solution**:
- Justify clearly in permission declaration
- Only use when absolutely necessary
- Consider foreground-only alternative

#### 4. Broken Functionality
**Reason**: Features don't work
**Solution**:
- Test on multiple Android versions
- Test on different screen sizes
- Handle offline gracefully

---

## Privacy Policy Requirements

### Required Sections

```markdown
# Privacy Policy for Radius

Last updated: [DATE]

## Information We Collect

### Personal Information
- Email address (for account creation)
- Display name (shown to other users)
- Profile photo (optional, shown to other users)

### Location Information
- Precise location (for nearby user discovery)
- We do NOT store location history

### Device Information
- Device identifiers (for analytics)
- Bluetooth identifiers (temporary, for proximity)

### Usage Information
- App interactions (for improving the app)
- Connection and chat activity

## How We Use Your Information

- To provide the proximity-based social features
- To enable connections between users
- To send notifications about nearby connections
- To improve app performance and fix bugs
- To prevent fraud and abuse

## Information Sharing

We share your information:
- Display name and photo with users you connect with
- Chat messages with your conversation partners
- Anonymized analytics with service providers

We do NOT:
- Sell your personal information
- Share your precise location with other users
- Share your data with advertisers

## Data Retention

- Account data: Until you delete your account
- Chat messages: Until conversation is deleted
- Location data: Not stored, used only in real-time

## Your Rights

You have the right to:
- Access your personal data
- Correct inaccurate data
- Delete your account and data
- Export your data
- Opt out of analytics

## Data Security

We protect your data using:
- Encryption in transit (TLS)
- Encryption at rest (Firebase)
- Access controls
- Regular security audits

## Children's Privacy

Radius is not intended for users under 13 years of age.
We do not knowingly collect data from children.

## Changes to This Policy

We will notify you of material changes via:
- In-app notification
- Email (if significant)

## Contact Us

[Your contact email]
[Your company address]
```

### GDPR Requirements (EU Users)
- [ ] Lawful basis for processing documented
- [ ] Data Processing Agreement with Firebase/Google
- [ ] Right to erasure implemented (delete account)
- [ ] Right to portability implemented (export data)
- [ ] Cookie consent (if web version)
- [ ] DPO contact if required

### CCPA Requirements (California Users)
- [ ] "Do Not Sell My Personal Information" disclosure
- [ ] Right to know what data is collected
- [ ] Right to delete personal information
- [ ] Right to opt-out of sale (even if you don't sell)
- [ ] Non-discrimination for exercising rights

---

## Firebase Configuration

### Production Setup

```dart
// lib/firebase_options_prod.dart
// Generated by FlutterFire CLI for production project

class ProdFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // Use different Firebase project for production
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PROD_API_KEY',
    appId: 'PROD_APP_ID',
    messagingSenderId: 'PROD_SENDER_ID',
    projectId: 'radius-prod',
    storageBucket: 'radius-prod.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'PROD_API_KEY',
    appId: 'PROD_APP_ID',
    messagingSenderId: 'PROD_SENDER_ID',
    projectId: 'radius-prod',
    storageBucket: 'radius-prod.appspot.com',
    iosBundleId: 'com.yourcompany.radius',
  );
}
```

### Environment Configuration

```dart
// lib/core/config/environment.dart

enum Environment { dev, staging, prod }

class AppConfig {
  static late Environment environment;
  
  static void initialize(Environment env) {
    environment = env;
  }
  
  static bool get isProduction => environment == Environment.prod;
  static bool get isDevelopment => environment == Environment.dev;
  
  static String get firebaseProject {
    switch (environment) {
      case Environment.dev:
        return 'radius-dev';
      case Environment.staging:
        return 'radius-staging';
      case Environment.prod:
        return 'radius-prod';
    }
  }
}
```

---

## Analytics Integration

### Firebase Analytics Setup

```dart
// lib/core/services/analytics/analytics_service.dart

import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  final FirebaseAnalytics _analytics;
  
  AnalyticsService() : _analytics = FirebaseAnalytics.instance;
  
  FirebaseAnalyticsObserver get observer => 
    FirebaseAnalyticsObserver(analytics: _analytics);
  
  // Screen tracking
  Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }
  
  // User properties
  Future<void> setUserId(String? userId) async {
    await _analytics.setUserId(id: userId);
  }
  
  Future<void> setUserProperty(String name, String value) async {
    await _analytics.setUserProperty(name: name, value: value);
  }
  
  // Custom events
  Future<void> logEvent(String name, [Map<String, dynamic>? params]) async {
    await _analytics.logEvent(name: name, parameters: params);
  }
  
  // Predefined events
  Future<void> logSignUp(String method) async {
    await _analytics.logSignUp(signUpMethod: method);
  }
  
  Future<void> logLogin(String method) async {
    await _analytics.logLogin(loginMethod: method);
  }
  
  Future<void> logShare(String contentType, String itemId) async {
    await _analytics.logShare(
      contentType: contentType,
      itemId: itemId,
      method: 'in_app',
    );
  }
}

// Event constants
abstract class AnalyticsEvents {
  static const String connectionRequested = 'connection_requested';
  static const String connectionAccepted = 'connection_accepted';
  static const String connectionRejected = 'connection_rejected';
  static const String messageSent = 'message_sent';
  static const String nearbyUserViewed = 'nearby_user_viewed';
  static const String profileUpdated = 'profile_updated';
  static const String bluetoothEnabled = 'bluetooth_enabled';
  static const String bluetoothDisabled = 'bluetooth_disabled';
  static const String proximityStarted = 'proximity_started';
  static const String proximityStopped = 'proximity_stopped';
}
```

### Usage in App

```dart
// In BLoC or service
_analyticsService.logEvent(
  AnalyticsEvents.connectionRequested,
  {'target_user_id': userId},
);

// In router
GoRouter(
  observers: [getIt<AnalyticsService>().observer],
  // ...
)
```

---

## Crash Reporting

### Firebase Crashlytics Setup

```dart
// lib/core/services/crash/crash_service.dart

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashService {
  final FirebaseCrashlytics _crashlytics;
  
  CrashService() : _crashlytics = FirebaseCrashlytics.instance;
  
  /// Initialize crash reporting
  Future<void> initialize() async {
    // Pass all uncaught errors to Crashlytics
    FlutterError.onError = (details) {
      _crashlytics.recordFlutterFatalError(details);
    };
    
    // Pass all uncaught async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
    
    // Enable in production only
    await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  }
  
  /// Set user identifier for crash reports
  Future<void> setUserId(String userId) async {
    await _crashlytics.setUserIdentifier(userId);
  }
  
  /// Clear user identifier on logout
  Future<void> clearUserId() async {
    await _crashlytics.setUserIdentifier('');
  }
  
  /// Add custom key-value for debugging
  Future<void> setCustomKey(String key, dynamic value) async {
    await _crashlytics.setCustomKey(key, value);
  }
  
  /// Log a message (shown in crash report timeline)
  Future<void> log(String message) async {
    await _crashlytics.log(message);
  }
  
  /// Record a non-fatal error
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    await _crashlytics.recordError(
      exception,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }
}
```

### Initialize in main.dart

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize crash reporting
  final crashService = CrashService();
  await crashService.initialize();
  
  // Run app with error boundary
  runApp(
    ErrorBoundary(
      onError: crashService.recordError,
      child: const RadiusApp(),
    ),
  );
}

// Error boundary widget
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Future<void> Function(dynamic, StackTrace?) onError;
  
  const ErrorBoundary({
    required this.child,
    required this.onError,
    super.key,
  });
  
  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  
  @override
  void initState() {
    super.initState();
  }
  
  static void _handleError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
  }
  
  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Something went wrong'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _hasError = false),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return widget.child;
  }
}
```

---

## Release Build Configuration

### Android (android/app/build.gradle)

```gradle
android {
    // ...
    
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            
            // Enable R8 full mode
            ndk {
                debugSymbolLevel 'FULL'
            }
        }
    }
    
    // Split APKs by ABI to reduce size
    splits {
        abi {
            enable true
            reset()
            include 'armeabi-v7a', 'arm64-v8a', 'x86_64'
            universalApk false
        }
    }
}
```

### iOS (ios/Runner/Release.xcconfig)

```
#include "Generated.xcconfig"

FLUTTER_BUILD_MODE=release
ENABLE_BITCODE=NO
STRIP_SWIFT_SYMBOLS=YES

// App Transport Security
INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsArbitraryLoads = NO
```

### ProGuard Rules (android/app/proguard-rules.pro)

```proguard
# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Crashlytics
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Flutter Blue Plus
-keep class com.boskokg.flutter_blue_plus.** { *; }

# Keep model classes (adjust package name)
-keep class com.yourcompany.radius.models.** { *; }
```

---

## Final Release Checklist

### Week Before Release

- [ ] Feature freeze - no new features
- [ ] Code freeze - only bug fixes
- [ ] Complete QA testing
- [ ] Beta testing with real users
- [ ] Performance profiling
- [ ] Security audit
- [ ] Legal review of privacy policy
- [ ] Prepare store listing assets
- [ ] Write release notes

### Day Before Release

- [ ] Final build created
- [ ] Build tested on real devices
- [ ] Version numbers verified
- [ ] Release notes finalized
- [ ] Screenshots are current
- [ ] Privacy policy published
- [ ] Support email ready
- [ ] Monitoring dashboards set up

### Release Day

- [ ] Upload build to App Store Connect
- [ ] Upload build/bundle to Play Console
- [ ] Submit for review (Apple)
- [ ] Start staged rollout (Google - 10%)
- [ ] Monitor crash reports
- [ ] Monitor analytics
- [ ] Monitor user feedback
- [ ] Respond to any review issues

### Post-Release

- [ ] Monitor crash-free rate (target: 99%+)
- [ ] Monitor app reviews
- [ ] Respond to user feedback
- [ ] Increase rollout percentage (Google)
- [ ] Plan hotfix if critical issues found
- [ ] Retrospective meeting
- [ ] Document lessons learned

---

## Monitoring & Support

### Key Metrics to Watch

| Metric | Target | Tool |
|--------|--------|------|
| Crash-free users | > 99% | Crashlytics |
| ANR rate (Android) | < 0.5% | Play Console |
| App startup time | < 3s | Firebase Performance |
| Daily active users | Track | Analytics |
| User retention (D1) | > 40% | Analytics |
| User retention (D7) | > 20% | Analytics |
| App rating | > 4.0 | Store Console |

### Support Preparation

- [ ] Support email configured
- [ ] FAQ document ready
- [ ] Known issues document
- [ ] Escalation process defined
- [ ] On-call rotation (if needed)

---

## Version Numbering

Follow semantic versioning: `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR**: Breaking changes, major redesign
- **MINOR**: New features, minor improvements  
- **PATCH**: Bug fixes, small improvements
- **BUILD**: Incremented for each build

Example: `1.2.3+45`
- Version 1.2.3 (shown to users)
- Build 45 (internal tracking)

```yaml
# pubspec.yaml
version: 1.0.0+1  # First release
version: 1.0.1+2  # Bug fix
version: 1.1.0+3  # New feature
version: 2.0.0+4  # Major update
```
