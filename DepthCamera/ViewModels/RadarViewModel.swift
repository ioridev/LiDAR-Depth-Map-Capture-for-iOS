import Foundation
import CoreBluetooth
import SwiftUI

class RadarViewModel: NSObject, ObservableObject {
    // CoreBluetooth properties
    private var centralManager: CBCentralManager!
    private var radarPeripheral: CBPeripheral?
    var arModel: ARViewModel?
    var deviceModel: DeviceViewModel?

    // Published properties for the SwiftUI View
    @Published var radarData: String = "No Data"
    @Published var isRadarConnected: Bool = false
    @Published var isBluetoothAvailable: Bool = false

    override init() {
        super.init()
        // Initialize CoreBluetooth Central Manager
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    func reconnectToSavedPeripheral() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("Max reconnect attempts reached. Scanning for peripherals...")
            reconnectAttempts = 0
//            centralManager.scanForPeripherals(withServices: nil)
            return
        }

        // Increment reconnect attempts
        reconnectAttempts += 1

        if let uuidString = UserDefaults.standard.string(forKey: "LastConnectedPeripheral"),
           let uuid = UUID(uuidString: uuidString),
           let restoredPeripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
            radarPeripheral = restoredPeripheral
            radarPeripheral?.delegate = self
            print("Attempting to reconnect to saved peripheral: \(restoredPeripheral.name ?? "Unknown Device")")
            centralManager.connect(restoredPeripheral)

            // Schedule the next attempt if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(reconnectAttempts * 2)) {
                if self.radarPeripheral?.state != .connected {
                    self.reconnectToSavedPeripheral()
                }
            }
        } else {
            print("Saved peripheral not found. Scanning for peripherals...")
            centralManager.scanForPeripherals(withServices: nil)
        }
    }

}

// MARK: - CBCentralManagerDelegate
extension RadarViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Retrieve the saved UUID
            if let uuidString = UserDefaults.standard.string(forKey: "LastConnectedPeripheral"),
               let uuid = UUID(uuidString: uuidString),
               let restoredPeripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first {
                // Reconnect to the saved peripheral
                radarPeripheral = restoredPeripheral
                radarPeripheral?.delegate = self
                print("Reconnecting to saved peripheral: \(restoredPeripheral.name ?? "Unknown Device")")
                centralManager.connect(restoredPeripheral)
            } else {
                // Scan for peripherals if no saved device exists
                // Check Bluetooth state
                isBluetoothAvailable = central.state == .poweredOn

                if isBluetoothAvailable {
                    print("Bluetooth is powered on. Scanning for devices...")
                    // Start scanning for peripherals (replace nil with specific service UUID if available)
                    centralManager.scanForPeripherals(withServices: nil)
                } else {
                    print("Bluetooth is not available or powered off.")
                    isRadarConnected = false
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name {
            print("Found device: \(name)")
        }
        
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            print("Advertised services: \(services)")
        }
        
        // Connect to the device if it's the desired one
        if let name = peripheral.name, name.contains("RCT715") {
            radarPeripheral = peripheral
            radarPeripheral?.delegate = self
            centralManager.stopScan()
            centralManager.connect(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Varia Radar")")
        isRadarConnected = true
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "LastConnectedPeripheral")
        radarPeripheral = peripheral
        radarPeripheral?.discoverServices([CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")]) // Replace nil with specific service UUID if known
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "Unknown error")")
        isRadarConnected = false
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "No error")")
        isRadarConnected = false
        // Attempt to reconnect to the saved peripheral
        reconnectToSavedPeripheral()
    }
}

// MARK: - CBPeripheralDelegate
extension RadarViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        for service in services {
            print("Discovered service: \(service.uuid)")
            // Replace UUID with the radar's specific service UUID
            if service.uuid == CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66") {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
//        if let error = error {
//            print("Error discovering characteristics: \(error.localizedDescription)")
//            return
//        }
//
//        guard let characteristics = service.characteristics else { return }
//        for characteristic in characteristics {
//            print("Discovered characteristic: \(characteristic.uuid)")
//            // Replace UUID with the radar's specific characteristic UUID
//            if characteristic.uuid == CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66") {
//                peripheral.setNotifyValue(true, for: characteristic)
//            }
//        }
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//        print("Received value for characteristic: \(characteristic.uuid)")
//        if let error = error {
//            print("Error updating value: \(error.localizedDescription)")
//            return
//        }
//
//        guard let data = characteristic.value else { return }
//
//        // Process radar data
//    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")

            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                print("Subscribing to notifications for characteristic: \(characteristic.uuid)")
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.properties.contains(.write) {
                let command = Data([0x01]) // Example command
                print("Writing command to characteristic: \(characteristic.uuid)")
                peripheral.writeValue(command, for: characteristic, type: .withResponse)
            } else {
                print("Characteristic \(characteristic.uuid) is not suitable for notifications or write commands.")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error receiving value for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            print("No data received for characteristic \(characteristic.uuid).")
            return
        }


        // Decode and analyze
        decodeRadarData(data)

//        let radarAlert = String(data: data, encoding: .utf8) ?? "Unknown Data"
//        DispatchQueue.main.async {
//            self.radarData = radarAlert
//        }
    }
    
    func decodeRadarData(_ data: Data) {
        let bytes = [UInt8](data) // Convert `Data` to a byte array

        guard bytes.count >= 4 else {
            if let arModel = arModel, arModel.isRecordingVideo {
                if let deviceModel = deviceModel {
                    deviceModel.sendMessage("stopped")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    arModel.stopVideoRecording()
                }
            }
            return
        }

        // Log raw bytes in hex
        let hexBytes = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("Raw data (hex): \(hexBytes)")

        // Log raw bytes in decimal
        let decimalBytes = data.map { String($0) }.joined(separator: ", ")
//        print("Raw data (decimal): [\(decimalBytes)]")

        // Decode packet fields
        let packetIdentifier = bytes[0]
        let threatIdentifier = bytes[1]
        let distance = bytes[2]
        let threatSpeed = bytes[3]

        guard let arModel = arModel else { return }
        
        if (threatSpeed < 40 && distance < 20 || threatSpeed >= 40 && distance < 60) && !arModel.isRecordingVideo {
            arModel.startVideoRecording()
            deviceModel?.sendMessage("started recording at: \(distance) \(threatSpeed)")
        }
        
//        print("Decoded Radar Data:")
//        print("  Packet Identifier: \(packetIdentifier)")
//        print("  Threat Identifier: \(threatIdentifier)")
//        print("  Distance to Threat: \(distance) meters")
//        print("  Threat Speed/Level: \(threatSpeedOrLevel) (possibly km/h)")
    }

}
