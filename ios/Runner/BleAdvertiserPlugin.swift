import Flutter
import CoreBluetooth
import UIKit

/**
 * Native iOS BLE Advertiser Plugin
 * 
 * Simplified BLE advertising using Service Data.
 * Broadcasts Service UUID (0xBEEF) with username in Service Data.
 * 
 * Note: iOS has limitations on BLE advertising in the background.
 * Advertising will stop when the app is backgrounded.
 */
class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {
    private var channel: FlutterMethodChannel?
    private var peripheralManager: CBPeripheralManager?
    private var isAdvertising = false
    private var currentServiceUUID: CBUUID?
    private var pendingServiceData: Data?
    private var pendingResult: FlutterResult?
    
    private static let channelName = "com.example.radius/ble_advertiser"

    override init() {
        super.init()
        // Keep advertising even when app is backgrounded so other devices can discover us.
        // Only stop advertising when app is terminated.
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

    // Only stop advertising when app is terminated, not when backgrounded.
    // This allows other devices to discover us while app is in recents.
    @objc private func appWillTerminate() {
        stopAdvertising()
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let serviceUuid16 = args["serviceUuid16"] as? String,
                  let serviceDataArray = args["serviceData"] as? FlutterStandardTypedData else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "serviceUuid16 and serviceData are required",
                    details: nil
                ))
                return
            }

            if serviceUuid16.count != 4 {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "serviceUuid16 must be 4 hex chars (e.g., BEEF)",
                    details: nil
                ))
                return
            }
            
            startAdvertising(
                serviceUuid16: serviceUuid16,
                serviceData: serviceDataArray.data,
                result: result
            )
            
        case "stopAdvertising":
            stopAdvertising()
            result(true)
            
        case "isAdvertising":
            result(isAdvertising)
            
        case "getCapabilities":
            result([
                "isAdvertisingSupported": true,
                "isMultipleAdvertisementSupported": false,
                "isBluetoothEnabled": peripheralManager?.state == .poweredOn
            ])
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startAdvertising(
        serviceUuid16: String,
        serviceData: Data,
        result: @escaping FlutterResult
    ) {
        if isAdvertising {
            result(true)
            return
        }
        
        // Store for later use
        // Use 16-bit UUID on-air.
        currentServiceUUID = CBUUID(string: serviceUuid16)
        pendingServiceData = serviceData
        pendingResult = result
        
        // Initialize peripheral manager if needed
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
            )
        }
        
        // Check if ready to advertise
        if peripheralManager?.state == .poweredOn {
            performAdvertising()
        }
        // Otherwise, wait for peripheralManagerDidUpdateState
    }
    
    private func performAdvertising() {
        guard let serviceUUID = currentServiceUUID,
              let serviceData = pendingServiceData else {
            pendingResult?(FlutterError(
                code: "INVALID_STATE",
                message: "No service data available",
                details: nil
            ))
            pendingResult = nil
            return
        }

        // iOS CoreBluetooth doesn't directly support Service Data in advertisements
        // like Android does. We use CBAdvertisementDataLocalNameKey and
        // CBAdvertisementDataServiceUUIDsKey as alternatives.
        //
        // For inter-device discovery, we'll advertise the Service UUID and use
        // the local name to encode the username (7 chars fits in the name field).
        let username = String(data: serviceData, encoding: .ascii) ?? ""
        
        // Configure advertisement data
        // Note: iOS advertising data has size limits. Keep it minimal.
        var advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ]
        
        // Use local name to carry the username (iOS limitation)
        // This is visible to scanning devices
        if !username.isEmpty {
            advertisementData[CBAdvertisementDataLocalNameKey] = username
        }
        
        NSLog("BleAdvertiser: Starting advertising with UUID: \(serviceUUID.uuidString), username: \(username)")
        
        // Start advertising
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
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            NSLog("BleAdvertiser: Bluetooth powered on")
            // If we have pending advertising request, start it
            if pendingServiceData != nil {
                performAdvertising()
            }
        case .poweredOff:
            isAdvertising = false
            pendingResult?(FlutterError(
                code: "BLE_OFF",
                message: "Bluetooth is powered off",
                details: nil
            ))
            pendingResult = nil
            channel?.invokeMethod("onAdvertisingError", arguments: "Bluetooth is powered off")
        case .unauthorized:
            isAdvertising = false
            pendingResult?(FlutterError(
                code: "BLE_UNAUTHORIZED",
                message: "Bluetooth permission denied",
                details: nil
            ))
            pendingResult = nil
            channel?.invokeMethod("onAdvertisingError", arguments: "Bluetooth permission denied")
        case .unsupported:
            isAdvertising = false
            pendingResult?(FlutterError(
                code: "BLE_UNSUPPORTED",
                message: "Bluetooth not supported",
                details: nil
            ))
            pendingResult = nil
            channel?.invokeMethod("onAdvertisingError", arguments: "Bluetooth not supported on this device")
        default:
            break
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            isAdvertising = false
            NSLog("BleAdvertiser: Failed to start advertising: \(error.localizedDescription)")
            pendingResult?(FlutterError(
                code: "ADVERTISING_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
            channel?.invokeMethod("onAdvertisingError", arguments: error.localizedDescription)
        } else {
            isAdvertising = true
            NSLog("BleAdvertiser: Advertising started successfully")
            pendingResult?(true)
        }
        pendingResult = nil
    }
}
