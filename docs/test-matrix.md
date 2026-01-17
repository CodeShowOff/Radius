# Device Test Matrix (Manual)

This doc is a practical checklist for validating BLE discovery/advertising behavior across real devices and OS versions.

Notes
- BLE behavior varies widely by OEM firmware and battery optimizers.
- Background discovery is *never* as reliable as foreground discovery.
- iOS background scanning is constrained; results may be fewer.
- Android background discovery is supported via PendingIntent and/or an opt-in Foreground Service (FGS).

## Common Setup (All Devices)

- Install the same build on **two devices** (Device A and Device B).
- Sign into different accounts on each device.
- Ensure Bluetooth is ON.
- Ensure Location services are ON (Android).
- Disable VPN / aggressive network firewalls if testing cloud features.

### Build/Run Commands

- Debug: `flutter run`
- Release (recommended for realistic behavior):
  - `flutter run --release --dart-define=RADIUS_MANUFACTURER_ID=0x1234`

### What to Observe

- Nearby screen shows users within 10–15 seconds in foreground.
- Diagnostics counters update (scan matches, start failures, permission denies).
- Production logs do not include raw BLE identifiers.

## Android (12/13/14) — Pixel / Samsung / Xiaomi

Matrix targets
- Pixel (AOSP-like): Android 12 / 13 / 14
- Samsung (One UI): Android 12 / 13 / 14
- Xiaomi (MIUI/HyperOS): Android 12 / 13 / 14

### A) Foreground Discovery

Steps
1. On both devices: open the app and navigate to Nearby.
2. Keep both devices on-screen (foreground).
3. Verify both devices appear in Nearby.

Pass criteria
- Both devices discover each other reliably.
- No repeated scan/advertise start failures.

### B) Background Discovery (PendingIntent)

Preconditions
- Enable the app’s “keep discovering in background” preference.
- Prefer continuous discovery mode.

Steps
1. Start discovery in the app.
2. Press Home to background the app.
3. Wait 30–60 seconds.
4. Bring the app foreground again.

Pass criteria
- When returning to foreground, buffered background scan results are ingested.
- Discovery continues without requiring a manual restart.

### C) Background Discovery (FGS opt-in)

Preconditions
- Enable “use foreground service for background discovery” preference.

Steps
1. Start continuous discovery.
2. Background the app.
3. Verify the OS shows an ongoing notification (FGS).
4. Return to the app.

Pass criteria
- Background discovery continues longer and more reliably than PendingIntent alone.
- Notification is present and stops when discovery is stopped.

### D) OEM Battery Optimizations (Samsung/Xiaomi)

Steps
1. Ensure the app is excluded from battery optimization (Settings → Battery).
2. Repeat tests B and C.

Pass criteria
- Background behavior improves or remains stable.

## iOS (15/16/17) — Central + Peripheral

Matrix targets
- iOS 15 / 16 / 17

Preconditions
- Info.plist includes `bluetooth-central` and `bluetooth-peripheral` background modes.
- Usage strings are present and user has granted Bluetooth permission.

### A) Foreground Central Discovery

Steps
1. Keep both devices in foreground on Nearby.
2. Verify discovery works.

Pass criteria
- Consistent discovery in foreground.

### B) Background Central Discovery (Service-UUID filtering)

Steps
1. Start discovery in foreground.
2. Background the app.
3. Keep the other device in foreground.
4. After 30–60 seconds, bring the backgrounded device back to foreground.

Pass criteria
- Some discovery events may still be delivered.
- Service-UUID filtered adverts are more likely to be observed than manufacturer-only payloads.

### C) Background Peripheral Advertising Limitations

Steps
1. Start advertising.
2. Background the app.
3. Observe whether the other device continues to discover it.

Pass criteria
- Advertising may be throttled/stopped when the app is suspended.
- The product should not assume advertising is continuous in background; foreground is recommended.

### D) Force-quit Behavior

Steps
1. Start discovery.
2. Force-quit the app (swipe away).
3. Attempt discovery from another device.

Expected
- iOS typically stops BLE operations when force-quit.

## Logging / Diagnostics Verification

- Release builds must not log:
  - anonymous IDs
  - device addresses
  - full manufacturer payloads
- Debug builds may log raw payloads for troubleshooting.

Recommended sanity checks
- Debug + forced safe logging: `flutter run --debug --dart-define=RADIUS_SAFE_BLE_LOGGING=true`
