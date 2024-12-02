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

    func saveData(image: UIImage) {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        // Get accelerometer data
        let x = motionManager.accelerometerData?.acceleration.x ?? 0.0
        let y = motionManager.accelerometerData?.acceleration.y ?? 0.0
        let z = motionManager.accelerometerData?.acceleration.z ?? 0.0

        // Get location data
        let lat = currentLocation?.coordinate.latitude ?? 0.0
        let lng = currentLocation?.coordinate.longitude ?? 0.0

        // Create a timestamped file name
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = "\(timestamp).txt"
        let imageFileName = "\(timestamp).jpg"

        // Save photo
        let imageURL = documentsURL.appendingPathComponent(imageFileName)
        if let imageData = image.jpegData(compressionQuality: 1.0) {
            try? imageData.write(to: imageURL)
        }

        // Save metadata to text file
        let textContent = """
        Accelerometer:
        X: \(x)
        Y: \(y)
        Z: \(z)
        Location:
        Latitude: \(lat)
        Longitude: \(lng)
        Timestamp: \(timestamp)
        """
        let textFileURL = documentsURL.appendingPathComponent(fileName)
        try? textContent.write(to: textFileURL, atomically: true, encoding: .utf8)

        print("Photo saved at: \(imageURL.path)")
        print("Metadata saved at: \(textFileURL.path)")
    }

    // CLLocationManagerDelegate - Update location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
