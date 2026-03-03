@echo off
REM Build script for Radius Android Release

echo ========================================
echo Radius Android Release Build Script
echo ========================================
echo.

REM Check if Flutter is installed
flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Flutter is not installed or not in PATH
    pause
    exit /b 1
)

echo Step 1: Cleaning previous builds...
call flutter clean

echo.
echo Step 2: Getting dependencies...
call flutter pub get

echo.
echo Step 3: Running code generation...
call dart run build_runner build --delete-conflicting-outputs

echo.
echo Choose build type:
echo 1. APK (for direct installation)
echo 2. AAB (for Google Play Store)
echo 3. Both
echo.
set /p choice="Enter your choice (1-3): "

if "%choice%"=="1" goto build_apk
if "%choice%"=="2" goto build_aab
if "%choice%"=="3" goto build_both
echo Invalid choice!
pause
exit /b 1

:build_apk
echo.
echo Building APKs (split per ABI)...
call flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
if %errorlevel% neq 0 (
    echo ERROR: APK build failed
    pause
    exit /b 1
)
echo.
echo ========================================
echo APKs built successfully!
echo Locations:
echo - build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
echo - build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
echo ========================================
goto end

:build_aab
echo.
echo Building AAB...
call flutter build appbundle --release
if %errorlevel% neq 0 (
    echo ERROR: AAB build failed
    pause
    exit /b 1
)
echo.
echo ========================================
echo AAB built successfully!
echo Location: build\app\outputs\bundle\release\app-release.aab
echo ========================================
goto end

:build_both
echo.
echo Building APKs (split per ABI)...
call flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
if %errorlevel% neq 0 (
    echo ERROR: APK build failed
    pause
    exit /b 1
)
echo.
echo Building AAB...
call flutter build appbundle --release
if %errorlevel% neq 0 (
    echo ERROR: AAB build failed
    pause
    exit /b 1
)
echo.
echo ========================================
echo Both builds completed successfully!
echo APKs:
echo - build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
echo - build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
echo AAB: build\app\outputs\bundle\release\app-release.aab
echo ========================================

:end
echo.
echo To install the APK on a connected device, run:
echo flutter install --release
echo.
pause
