# Radius

Radius is a Flutter social app focused on helping people connect with others nearby and in interest-based communities.

## About

This repository contains the mobile client, Firebase configuration, and Firebase Cloud Functions used by Radius.

## Key Features

- Proximity-based discovery using Bluetooth LE
- Nearby and random group discovery/chat
- 1:1 messaging with media support (images, audio, documents)
- Connection requests and social profiles
- Local posts/news feed
- Nearby help request flows
- Firebase push notifications (FCM + Cloud Functions)

## Tech Stack

- Flutter + Dart
- Firebase (Auth, Firestore, Storage, Realtime Database, Messaging, Functions)
- BLoC architecture (`flutter_bloc`)
- Node.js/TypeScript Firebase Functions

## Developer Setup

### Prerequisites

- Flutter SDK (Dart SDK included)
- Android Studio and/or Xcode
- Node.js 22 (for `functions/`)
- Firebase CLI

### 1) Install dependencies

```bash
flutter pub get
cd functions
npm install
cd ..
```

### 2) Configure Firebase

- Add `android/app/google-services.json`
- Add `ios/Runner/GoogleService-Info.plist`
- Ensure `lib/firebase_options.dart` matches your Firebase project (via FlutterFire CLI if needed)

### 3) Optional backend deploys

```bash
firebase deploy --only firestore:rules,storage
firebase deploy --only functions
```

## Run Locally

```bash
flutter run --dart-define=RADIUS_ENV=dev
```

Other environments:

- `--dart-define=RADIUS_ENV=staging`
- `--dart-define=RADIUS_ENV=prod`

## Validate

```bash
flutter analyze
flutter test
```

## Build

### Android

```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS (macOS only)

```bash
flutter build ios --release
flutter build ipa --release
```

## Useful Docs

- `/docs/QUICK_REFERENCE.md`
- `/docs/NOTIFICATION_SETUP.md`
- `/docs/FIREBASE_STORAGE_SETUP.md`
- `/docs/CHAT_MEDIA_FEATURES.md`
