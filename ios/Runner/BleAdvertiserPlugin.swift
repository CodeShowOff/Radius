import Flutter
import CoreBluetooth
import UIKit

/**
 * Native iOS BLE Advertiser Plugin
 *
 * Broadcasts username-encoded Service UUID for iOS background compatibility.
 *
 * Background advertising:
 *  - Uses the `bluetooth-peripheral` UIBackgroundMode so CoreBluetooth
 *    continues advertising when the app is suspended.
 *  - Uses state-restoration (`CBPeripheralManagerOptionRestoreIdentifierKey`)
 *    so iOS can re-launch the app if it is killed and re-start advertising.
 *  - **ENCODES USERNAME INTO UUID** - When backgrounded, iOS preserves service UUIDs
 *    but strips LocalName and Service Data. We encode the username into the UUID itself.
 *
 * UUID Format: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX (username encoded in XXXX sections)
 *
 * `startForegroundService` / `stopForegroundService` are accepted on the
 * MethodChannel for API parity with Android; they map to the same
 * persistent-advertising behaviour since iOS has no foreground-service concept.
 */
class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {
    private var channel: FlutterMethodChannel?
    private var peripheralManager: CBPeripheralManager?
    private var isAdvertising = false
    private var currentServiceUUID: CBUUID?
    private var pendingServiceData: Data?
    private var pendingResult: FlutterResult?

    /// Whether persistent (background) advertising was requested.
    private var persistentAdvertisingRequested = false {
        didSet { UserDefaults.standard.set(persistentAdvertisingRequested, forKey: "ble_adv_persistent") }
    }

    /// Saved advertising parameters for restore / BT-toggle restart.
    /// Persisted in UserDefaults so state-restoration after kill works.
    private var savedServiceUuid16: String?
    private var savedUsername: String?

    private static let channelName = "com.codeshowoff.radius/ble_advertiser"
    private static let restoreIdentifier = "com.codeshowoff.radius.blePeripheral"

    override init() {
        // Restore saved parameters from UserDefaults (survives app kill).
        let defaults = UserDefaults.standard
        savedServiceUuid16 = defaults.string(forKey: "ble_adv_uuid16")
        savedUsername = defaults.string(forKey: "ble_adv_username")
        // Must read before super.init sets didSet
        let wasPersistent = defaults.bool(forKey: "ble_adv_persistent")

        super.init()

        persistentAdvertisingRequested = wasPersistent

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopAdvertising()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = BleAdvertiserPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    @objc private func appWillTerminate() {
        // If persistent advertising is on, do NOT stop — iOS state-restoration
        // will re-launch the app and resume advertising.
        if !persistentAdvertisingRequested {
            stopAdvertising()
        }
    }

    // MARK: - MethodChannel handler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let serviceUuid16 = args["serviceUuid16"] as? String,
                  let serviceDataArray = args["serviceData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "serviceUuid16 and serviceData are required",
                                    details: nil))
                return
            }
            if serviceUuid16.count != 4 {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "serviceUuid16 must be 4 hex chars",
                                    details: nil))
                return
            }
            startAdvertising(serviceUuid16: serviceUuid16,
                             serviceData: serviceDataArray.data,
                             persistent: false,
                             result: result)

        case "stopAdvertising":
            persistentAdvertisingRequested = false
            stopAdvertising()
            clearSavedParameters()
            result(true)

        case "isAdvertising":
            result(isAdvertising)

        case "getCapabilities":
            result([
                "isAdvertisingSupported": true,
                "isMultipleAdvertisementSupported": false,
                "isBluetoothEnabled": peripheralManager?.state == .poweredOn
            ])

        // ── Foreground-service parity with Android ────────────────────
        case "startForegroundService":
            guard let args = call.arguments as? [String: Any],
                  let serviceUuid16 = args["serviceUuid16"] as? String,
                  let serviceDataArray = args["serviceData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "serviceUuid16 and serviceData are required",
                                    details: nil))
                return
            }
            startAdvertising(serviceUuid16: serviceUuid16,
                             serviceData: serviceDataArray.data,
                             persistent: true,
                             result: result)

        case "stopForegroundService":
            persistentAdvertisingRequested = false
            stopAdvertising()
            clearSavedParameters()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Advertising

    private func startAdvertising(serviceUuid16: String,
                                  serviceData: Data,
                                  persistent: Bool,
                                  result: @escaping FlutterResult) {
        if isAdvertising {
            if persistent { persistentAdvertisingRequested = true }
            result(true)
            return
        }

        // Note: serviceUuid16 is ignored - we encode username into UUID instead
        pendingServiceData = serviceData
        pendingResult = result

        savedServiceUuid16 = serviceUuid16
        savedUsername = String(data: serviceData, encoding: .ascii)

        // Persist to UserDefaults so state-restoration after app kill works.
        let defaults = UserDefaults.standard
        defaults.set(serviceUuid16, forKey: "ble_adv_uuid16")
        defaults.set(savedUsername, forKey: "ble_adv_username")

        if persistent { persistentAdvertisingRequested = true }

        // Create (or re-use) the peripheral manager with state-restoration.
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [
                    CBPeripheralManagerOptionShowPowerAlertKey: true,
                    CBPeripheralManagerOptionRestoreIdentifierKey: BleAdvertiserPlugin.restoreIdentifier
                ]
            )
        }

        if peripheralManager?.state == .poweredOn {
            performAdvertising()
        }
        // Otherwise wait for peripheralManagerDidUpdateState
    }

    private func performAdvertising() {
        guard let serviceData = pendingServiceData else {
            pendingResult?(FlutterError(code: "INVALID_STATE",
                                        message: "No service data available",
                                        details: nil))
            pendingResult = nil
            return
        }

        let username = String(data: serviceData, encoding: .ascii) ?? ""

        // NEW: Encode username into UUID for iOS background compatibility
        guard let encodedUuidString = BleUuidEncoder.encodeUsernameToUuid(username) else {
            pendingResult?(FlutterError(code: "ENCODING_ERROR",
                                        message: "Failed to encode username into UUID",
                                        details: nil))
            pendingResult = nil
            return
        }
        
        let encodedUUID = CBUUID(string: encodedUuidString)
        currentServiceUUID = encodedUUID

        // iOS Background Behavior:
        // When backgrounded, iOS preserves the Service UUID (which now contains the username)
        // but strips LocalName and Service Data. The encoded UUID persists!
        var advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [encodedUUID],  // ✅ Persists in background with username encoded
        ]
        
        // Optional: Add LocalName and Service Data for foreground (will be stripped in background)
        // This provides backward compatibility with old Android scanners
        advertisementData[CBAdvertisementDataLocalNameKey] = username
        advertisementData[CBAdvertisementDataServiceDataKey] = [CBUUID(string: "BEEF"): serviceData]

        NSLog("BleAdvertiser: Starting advertising with encoded UUID: \(encodedUuidString), user: \(username), persistent: \(persistentAdvertisingRequested)")
        NSLog("BleAdvertiser: [NEW] Username IS encoded in UUID and will persist in background!")

        peripheralManager?.startAdvertising(advertisementData)
    }

    private func stopAdvertising() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
            NSLog("BleAdvertiser: Advertising stopped")
        }
        pendingResult = nil
    }

    /// Clears persisted parameters from UserDefaults.
    private func clearSavedParameters() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "ble_adv_uuid16")
        defaults.removeObject(forKey: "ble_adv_username")
        defaults.removeObject(forKey: "ble_adv_persistent")
        savedServiceUuid16 = nil
        savedUsername = nil
    }

    /// Re-start advertising from saved parameters (BT toggle or state restore).
    private func restartAdvertisingIfNeeded() {
        guard persistentAdvertisingRequested,
              let username = savedUsername else { return }

        let data = Data(username.utf8)
        pendingServiceData = data
        performAdvertising()
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            NSLog("BleAdvertiser: Bluetooth powered on")
            if pendingServiceData != nil {
                performAdvertising()
            } else {
                // BT was toggled off→on — restart if persistent mode active
                restartAdvertisingIfNeeded()
            }

        case .poweredOff:
            isAdvertising = false
            pendingResult?(FlutterError(code: "BLE_OFF",
                                        message: "Bluetooth is powered off",
                                        details: nil))
            pendingResult = nil
            channel?.invokeMethod("onAdvertisingError",
                                  arguments: "Bluetooth is powered off")

        case .unauthorized:
            isAdvertising = false
            pendingResult?(FlutterError(code: "BLE_UNAUTHORIZED",
                                        message: "Bluetooth permission denied",
                                        details: nil))
            pendingResult = nil
            channel?.invokeMethod("onAdvertisingError",
                                  arguments: "Bluetooth permission denied")

        case .unsupported:
            isAdvertising = false
            pendingResult?(FlutterError(code: "BLE_UNSUPPORTED",
                                        message: "Bluetooth not supported",
                                        details: nil))
            pendingResult = nil
            channel?.invokeMethod("onAdvertisingError",
                                  arguments: "Bluetooth not supported on this device")

        default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager,
                                              error: Error?) {
        if let error = error {
            isAdvertising = false
            NSLog("BleAdvertiser: Failed: \(error.localizedDescription)")
            pendingResult?(FlutterError(code: "ADVERTISING_FAILED",
                                        message: error.localizedDescription,
                                        details: nil))
            channel?.invokeMethod("onAdvertisingError",
                                  arguments: error.localizedDescription)
        } else {
            isAdvertising = true
            NSLog("BleAdvertiser: Advertising started successfully")
            pendingResult?(true)
        }
        pendingResult = nil
    }

    // MARK: - State Restoration

    /// Called by iOS when the app is re-launched after being killed while a
    /// CBPeripheralManager with a restore-identifier was active.
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           willRestoreState dict: [String: Any]) {
        NSLog("BleAdvertiser: State restored by iOS")
        // Re-flag persistent mode and let peripheralManagerDidUpdateState
        // trigger restartAdvertisingIfNeeded once BT is .poweredOn.
        if savedServiceUuid16 != nil {
            persistentAdvertisingRequested = true
        }
    }
}
