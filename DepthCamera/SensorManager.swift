//
//  SensorManager.swift
//  DepthCamera
//
//  Created by Brian Toone on 12/2/24.
//


import Foundation
import CoreLocation
import CoreMotion

class SensorManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let fileManager = FileManager.default
    @Published var isRunning = false
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Request location authorization if not yet determined
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        // Start motion updates
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1 // Adjust as needed
            motionManager.startAccelerometerUpdates()
        }

        // Start location updates
        locationManager.startUpdatingLocation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        // Stop motion updates
        motionManager.stopAccelerometerUpdates()

        // Stop location updates
        locationManager.stopUpdatingLocation()
    }
    
    func loadData(metadataFileURL: URL) -> Metadata? {
        do {
            let data = try Data(contentsOf: metadataFileURL)
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(Metadata.self, from: data)
            return metadata
        } catch {
            print("Error reading or decoding JSON:", error)
            return nil
        }
    }

    func saveData(textFileURL: URL, timestamp: Double, cameraIntrinsics: Matrix3x3) -> Metadata {

        // Get accelerometer data
        let x = motionManager.accelerometerData?.acceleration.x ?? 0.0
        let y = motionManager.accelerometerData?.acceleration.y ?? 0.0
        let z = motionManager.accelerometerData?.acceleration.z ?? 0.0

        // Get location data
        let lat = currentLocation?.coordinate.latitude ?? 0.0
        let lng = currentLocation?.coordinate.longitude ?? 0.0

        // Save metadata to text file

        // Then, in your code:
        let data = Metadata(
            Accelerometer: AccelerometerData(X: x, Y: y, Z: z),
            Location: LocationData(Latitude: lat, Longitude: lng),
            Timestamp: timestamp,
            CameraIntrinsics: cameraIntrinsics
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(data)            
            // Write to file
            try encoded.write(to: textFileURL)

        } catch {
            print("Error encoding or writing JSON:", error)
        }
        print("Metadata saved at: \(textFileURL.path)")
        return data
    }

    // CLLocationManagerDelegate - Update location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
