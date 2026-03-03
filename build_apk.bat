@echo off

echo Building Flutter APK...
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64