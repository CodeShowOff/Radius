import Flutter
import CoreBluetooth
import UIKit

/**
 * Native iOS BLE Advertiser Plugin
 * 
 * Provides BLE peripheral/advertising functionality using CoreBluetooth's
 * CBPeripheralManager API.
 */
class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {
    private var channel: FlutterMethodChannel?
    private var peripheralManager: CBPeripheralManager?
    private var isAdvertising = false
    private var currentServiceUUID: CBUUID?
    private var currentManufacturerId: UInt16 = {
        #if DEBUG
        return 0xFFFF
        #else
        return 0
        #endif
    }()
    
    private static let channelName = "com.example.radius/ble_advertiser"
    private static let radiusServiceUUID = "00001234-0000-1000-8000-00805f9b34fb"

    // Signature to distinguish Radius packets from other apps.
    // Format: ['R','D', version=1] + packedAnonymousIdBytes
    private static let radiusMagic: [UInt8] = [0x52, 0x44, 0x01]
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = BleAdvertiserPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let anonymousId = args["anonymousId"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "anonymousId is required",
                    details: nil
                ))
                return
            }
            
            let serviceUuid = args["serviceUuid"] as? String ?? BleAdvertiserPlugin.radiusServiceUUID
            if let m = args["manufacturerId"] as? NSNumber {
                self.currentManufacturerId = UInt16(truncatingIfNeeded: m.uint16Value)
            }
            startAdvertising(anonymousId: anonymousId, serviceUuid: serviceUuid, result: result)
            
        case "stopAdvertising":
            stopAdvertising()
            result(true)
            
        case "isAdvertising":
            result(isAdvertising)
            
        case "updateAdvertisement":
            guard let args = call.arguments as? [String: Any],
                  let anonymousId = args["anonymousId"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "anonymousId is required",
                    details: nil
                ))
                return
            }
            
            let serviceUuid = args["serviceUuid"] as? String ?? BleAdvertiserPlugin.radiusServiceUUID
            if let m = args["manufacturerId"] as? NSNumber {
                self.currentManufacturerId = UInt16(truncatingIfNeeded: m.uint16Value)
            }
            
            // Restart advertising with new data
            stopAdvertising()
            startAdvertising(anonymousId: anonymousId, serviceUuid: serviceUuid, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startAdvertising(
        anonymousId: String,
        serviceUuid: String,
        result: @escaping FlutterResult
    ) {
        if isAdvertising {
            result(true)
            return
        }
        
        // Initialize peripheral manager if needed
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
            )
        }
        
        // Store the service UUID
        currentServiceUUID = CBUUID(string: serviceUuid)
        
        // Wait for peripheral manager to be ready
        if peripheralManager?.state == .poweredOn {
            performAdvertising(anonymousId: anonymousId)
            result(true)
        } else {
            // Will be called in peripheralManagerDidUpdateState
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.peripheralManager?.state == .poweredOn {
                    self.performAdvertising(anonymousId: anonymousId)
                    result(true)
                } else {
                    result(FlutterError(
                        code: "BLE_UNAVAILABLE",
                        message: "Bluetooth is not available or powered on",
                        details: nil
                    ))
                }
            }
        }
    }
    
    private func performAdvertising(anonymousId: String) {
        guard let serviceUUID = currentServiceUUID else { return }

        // Manufacturer payload format (Apple): first 2 bytes are company ID (little-endian),
        // followed by manufacturer-specific bytes. We pack the anonymous ID hex into bytes
        // to keep payload small and consistent with Android.
        let idBytes = hexToBytes(anonymousId)
        var manufacturer = Data()
        manufacturer.append(UInt8(currentManufacturerId & 0x00FF))
        manufacturer.append(UInt8((currentManufacturerId & 0xFF00) >> 8))
        manufacturer.append(contentsOf: BleAdvertiserPlugin.radiusMagic)
        manufacturer.append(contentsOf: idBytes)

        // Configure advertisement data
        let advertisementData: [String: Any] = [
            CBAdvertisementDataManufacturerDataKey: manufacturer,
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ]
        
        // Start advertising
        peripheralManager?.startAdvertising(advertisementData)
        isAdvertising = true
    }

    private func hexToBytes(_ hex: String) -> [UInt8] {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count % 2 != 0 { return [] }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index..<nextIndex]
            if let num = UInt8(byteString, radix: 16) {
                bytes.append(num)
            } else {
                return []
            }
            index = nextIndex
        }
        return bytes
    }
    
    private func stopAdvertising() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            // Bluetooth is ready
            break
        case .poweredOff:
            isAdvertising = false
            channel?.invokeMethod("onAdvertisingError", arguments: "Bluetooth is powered off")
        case .unauthorized:
            isAdvertising = false
            channel?.invokeMethod("onAdvertisingError", arguments: "Bluetooth permission denied")
        case .unsupported:
            isAdvertising = false
            channel?.invokeMethod("onAdvertisingError", arguments: "Bluetooth not supported on this device")
        default:
            break
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            isAdvertising = false
            channel?.invokeMethod("onAdvertisingError", arguments: error.localizedDescription)
        } else {
            isAdvertising = true
        }
    }
}
