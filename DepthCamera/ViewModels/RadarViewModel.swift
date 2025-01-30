import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - Radar Data Model
struct RadarRecord: Identifiable {
    let id: Int
    let raw: String
    let interpreted: String
}

extension Date {
    func formattedLogTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss.SSS" // Example: 20250125_143210
        formatter.timeZone = TimeZone(abbreviation: "UTC") // Use UTC
        return formatter.string(from: self)
    }
}

class RadarViewModel: NSObject, ObservableObject {
    // CoreBluetooth properties
    private var centralManager: CBCentralManager!
    private var radarPeripheral: CBPeripheral?
    var arModel: ARViewModel?
    var deviceModel: DeviceViewModel?
    
    // Published properties for the SwiftUI View
    @Published var dataRecords: [RadarRecord] = []
    @Published var isRadarConnected: Bool = false
    @Published var isBluetoothAvailable: Bool = false
    @Published var isScanning: Bool = false
    
    // used to give unique id for each record
    private var counter = 0

    private var logFileURL: URL {
        // Get the app's documents directory
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("radar_logs.txt")
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        createLogFileIfNeeded()
    }

    private func createLogFileIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
    }

    func scanForDevices() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not available or powered on.")
            return
        }
        
        isScanning = true
        print("Starting scan for devices...")
        centralManager.scanForPeripherals(withServices: nil)
    }
    
    // for reconnecting tries ...
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    
    func reconnectToSavedPeripheral() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("Max reconnect attempts reached. Click reconnect button if you want to reconnect...")
            reconnectAttempts = 0
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
    
    private func rotateLogFile() {
        let fileManager = FileManager.default

        // Check if the log file exists
        guard fileManager.fileExists(atPath: logFileURL.path) else { return }

        // Generate a new filename with a timestamp
        let timestamp = Date().formattedLogTimestamp()
        let rotatedLogFileURL = logFileURL.deletingLastPathComponent().appendingPathComponent("radar_logs_\(timestamp).txt")

        do {
            // Rename the current log file
            try fileManager.moveItem(at: logFileURL, to: rotatedLogFileURL)
            print("Log file rotated: \(rotatedLogFileURL.path)")

            // Create a new empty log file
            fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        } catch {
            print("Failed to rotate log file: \(error.localizedDescription)")
        }
    }
    
    private func truncateLogFileIfNeeded(maxSize: Int = 100_000) {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: logFileURL.path) else { return }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? Int, fileSize > maxSize {
                // Rotate the log file before truncating
                rotateLogFile()
            }
        } catch {
            print("Failed to check log file size: \(error.localizedDescription)")
        }
    }
    
}

// MARK: - CBCentralManagerDelegate
extension RadarViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            isBluetoothAvailable = true
            
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
        // Need to add names for all the other compatible radars
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
        radarPeripheral?.discoverServices([CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")]) // According to garmin forum posts, this UUID seems to be the radar one and spans all their various models.
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "Unknown error")")
        isRadarConnected = false
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "No error")")
        isRadarConnected = false
        if let deviceModel = deviceModel {
            deviceModel.sendMessage("disconnected")
        }
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
                    if let deviceModel = deviceModel {
                        deviceModel.sendMessage("connected")
                    }
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.properties.contains(.write) {
//                    let command = Data([0x01]) // Example command
//                    print("Writing command to characteristic: \(characteristic.uuid)")
//                    peripheral.writeValue(command, for: characteristic, type: .withResponse)
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
        
        // Decode packet fields
        // Just record the first
        for i in 0..<bytes.count/4 {
            let packetIdentifier = bytes[0+i*4]
            let threatIdentifier = bytes[1+i*4]
            let distance = bytes[2+i*4]
            let threatSpeed = bytes[3+i*4]
            
            guard let arModel = arModel else { return }

            // slow approaching ... wait until 20m ... fast approaching ... wait until 60m
            if (threatSpeed < 40 && distance < 20 || threatSpeed >= 40 && distance < 60) && !arModel.isRecordingVideo {
                deviceModel?.sendMessage("\(distance)m \(threatSpeed)km/h")
                arModel.startVideoRecording()
            }
            
            let raw = String(format: "%02X %02X %02X %02X", packetIdentifier, threatIdentifier, distance, threatSpeed)
            let interpreted = "Distance: \(distance)m, Speed: \(threatSpeed)km/h"
            let newRecord = RadarRecord(id: counter, raw: raw, interpreted: interpreted)
            counter += 1
            
            // Append the record
            DispatchQueue.main.async {
                self.dataRecords.append(newRecord)
            }
            
            saveLog(raw: raw, interpreted: "\(distance)m, \(threatSpeed)km/h")

        }
        
    }
    
    // timestamp is UTC
    private func saveLog(raw: String, interpreted: String) {
        truncateLogFileIfNeeded(maxSize: 100_000) // Check file size before appending
        let timestamp = Date().formattedLogTimestamp() // Use UTC timestamp

        // Use an ordered array of key-value tuples instead of a dictionary
        let logEntry: [(String, String)] = [
            ("timestamp", timestamp),
            ("raw", raw),
            ("info", interpreted)
        ]

        do {
            // Convert the ordered array into a JSON object
            let jsonData = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: logEntry), options: [])

            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let formattedLog = jsonString + "\n"

                // Write the JSON string to the log file
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(formattedLog.data(using: .utf8)!)
                } else {
                    // If the file handle couldn't open, create the log file
                    try formattedLog.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("Failed to save log entry: \(error.localizedDescription)")
        }
    }

    
}
