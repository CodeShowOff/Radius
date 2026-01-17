#!/bin/bash
# Build script for Radius iOS Release

echo "========================================"
echo "Radius iOS Release Build Script"
echo "========================================"
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter is not installed or not in PATH"
    exit 1
fi

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "ERROR: iOS builds can only be done on macOS"
    exit 1
fi

echo "Step 1: Cleaning previous builds..."
flutter clean

echo ""
echo "Step 2: Getting dependencies..."
flutter pub get

echo ""
echo "Step 3: Running code generation..."
dart run build_runner build --delete-conflicting-outputs

echo ""
echo "Step 4: Installing CocoaPods dependencies..."
cd ios
pod install
pod update
cd ..

echo ""
echo "Choose build type:"
echo "1. iOS build (for running on device from Xcode)"
echo "2. IPA (for TestFlight/App Store)"
echo ""
read -p "Enter your choice (1-2): " choice

case $choice in
    1)
        echo ""
        echo "Building iOS..."
        flutter build ios --release
        if [ $? -ne 0 ]; then
            echo "ERROR: iOS build failed"
            exit 1
        fi
        echo ""
        echo "========================================"
        echo "iOS build completed successfully!"
        echo "Open ios/Runner.xcworkspace in Xcode to run on device"
        echo "========================================"
        ;;
    2)
        echo ""
        echo "Building IPA..."
        flutter build ipa --release
        if [ $? -ne 0 ]; then
            echo "ERROR: IPA build failed"
            exit 1
        fi
        echo ""
        echo "========================================"
        echo "IPA built successfully!"
        echo "Location: build/ios/ipa/radius.ipa"
        echo ""
        echo "To upload to App Store Connect:"
        echo "1. Open Xcode → Window → Organizer"
        echo "2. Or use Apple Transporter app"
        echo "========================================"
        ;;
    *)
        echo "Invalid choice!"
        exit 1
        ;;
esac

echo ""
echo "Note: Make sure you have:"
echo "- Valid Apple Developer account"
echo "- Proper signing certificate and provisioning profile"
echo "- Updated Bundle Identifier in Xcode"
echo ""
