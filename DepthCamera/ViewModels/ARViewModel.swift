import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics
import tiff_ios

// For storing the camera intrinsics for calculating perpendicular distances)
struct AccelerometerData: Codable {
    let X: Double
    let Y: Double
    let Z: Double
}

struct LocationData: Codable {
    let Latitude: Double
    let Longitude: Double
}

struct Matrix3x3: Codable {
    let rows: [[Float]]  // 3 arrays, each with 3 floats
    
    init(_ m: simd_float3x3?) {
        if let m = m {
            // Extract each element row-by-row
            rows = [
                [m[0,0], m[0,1], m[0,2]],
                [m[1,0], m[1,1], m[1,2]],
                [m[2,0], m[2,1], m[2,2]]
            ]
        } else {
            rows = [
                [1580.0, 0.0, 0.0],
                [0.0, 1580.0, 0.0],
                [960.0, 720.0, 1.0]
            ]
        }
    }
    
    /// Reconstruct a simd_float3x3 from this struct
    func toSIMD() -> simd_float3x3 {
        // rows[0] = [fx,  0,   ...]
        // etc.
        let r0 = rows[0], r1 = rows[1], r2 = rows[2]
        return simd_float3x3([
            SIMD3<Float>(r0[0], r0[1], r0[2]),
            SIMD3<Float>(r1[0], r1[1], r1[2]),
            SIMD3<Float>(r2[0], r2[1], r2[2])
        ])
    }
    
    func extractARKitIntrinsics() -> (fx: Float, fy: Float, cx: Float, cy: Float) {
        let fx = rows[0][0]
        let fy = rows[1][1]
        let cx = rows[2][0]
        let cy = rows[2][1]
        return (fx, fy, cx, cy)
    }
}

class ARViewModel: NSObject, ARSessionDelegate, ObservableObject {
    private var sensorManager = SensorManager()
    private var latestDepthMap: CVPixelBuffer?
    private var latestImage: CVPixelBuffer?
    private var latestFrame: ARFrame?
    
    @Published var isRecordingVideo = false
    private var videoTimer: Timer?
    private var videoStartTime: TimeInterval?
    private var videoDirectoryURL: URL?
    @Published var lastCapture: UIImage? = nil {
        didSet {
            print("lastCapture was set.")
        }
    }
    
    private var model = DataModel() // ai model
    @Published var lastSemanticImage: UIImage?
    
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestDepthMap = frame.sceneDepth?.depthMap
        latestImage = frame.capturedImage
        latestFrame = frame
    }
    
    func saveDepthMap() {
        guard let depthMap = latestDepthMap, let image = latestImage, let frame = latestFrame else {
            print("Depth map or image is not available.")
            return
        }
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())
        let dateDirURL = documentsDir.appendingPathComponent(dateString)
        
        do {
            try FileManager.default.createDirectory(at: dateDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create directory: \(error)")
            return
        }
        
        let timestamp = Date().timeIntervalSince1970*1000
        let depthFileURL = dateDirURL.appendingPathComponent("\(timestamp)_depth.tiff")
        let imageFileURL = dateDirURL.appendingPathComponent("\(timestamp)_image.jpg")
        let metaFileURL = dateDirURL.appendingPathComponent("\(timestamp)_meta.txt")
        sensorManager.saveData(textFileURL: metaFileURL, timestamp: timestamp, cameraIntrinsics: Matrix3x3(latestFrame?.camera.intrinsics))
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)

        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        
        
        DispatchQueue.main.async {
            self.lastCapture = uiImage
        }
             
        print("Depth map saved to \(depthFileURL)")
        print("Image saved to \(imageFileURL)")
    }
    
    private func captureDepthImage() {
        guard let depthMap = latestDepthMap, let image = latestImage, let videoDirURL = videoDirectoryURL else {
            print("Depth map or image is not available.")
            return
        }

        // Get current UNIX timestamp for the frame
        let frameTimestamp = Date().timeIntervalSince1970*1000

        // File URLs for depth map and image
        let depthFileURL = videoDirURL.appendingPathComponent("\(Int(frameTimestamp))_depth.tiff")
        let imageFileURL = videoDirURL.appendingPathComponent("\(Int(frameTimestamp))_image.jpg")
        let metaFileURL = videoDirURL.appendingPathComponent("\(Int(frameTimestamp))_meta.txt")
        let metadata = sensorManager.saveData(textFileURL: metaFileURL, timestamp: frameTimestamp, cameraIntrinsics: Matrix3x3(latestFrame?.camera.intrinsics))
    
        // Save the depth map and image
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)

        // Update the last captured image for thumbnail
        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        DispatchQueue.main.async {
            self.lastCapture = uiImage
        }
        
        if lastSemanticImage == nil {
            let context = CIContext()
            let ciImage = CIImage(cvPixelBuffer: image)
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                lastSemanticImage = UIImage(cgImage: cgImage)
                let labelattributes = model.performInference(ciImage, depthURL: depthFileURL, metadata: metadata)
            }
        }
        
        print("Saved depth map and image at \(frameTimestamp)")
    }
    
    func startVideoRecording() {
            guard !isRecordingVideo else { return }
        
            isRecordingVideo = true
            UIScreen.main.brightness = CGFloat(0.01)

            // tell the sensor manager to start collecting location and accelerometer data
            sensorManager.start()
        
            // Get UNIX timestamp for the start time
            videoStartTime = Date().timeIntervalSince1970

            // Create directory named with the UNIX start time
            if let startTime = videoStartTime {
                let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                videoDirectoryURL = documentsDir.appendingPathComponent("\(Int(startTime))")
                do {
                    try FileManager.default.createDirectory(at: videoDirectoryURL!, withIntermediateDirectories: true, attributes: nil)
                    print("Created directory: \(videoDirectoryURL!.path)")
                } catch {
                    print("Failed to create directory: \(error)")
                    isRecordingVideo = false
                    return
                }
            }

            // Start a timer to capture depth images every second
            videoTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                self.captureDepthImage()
            }
        }

        func stopVideoRecording() {
            guard isRecordingVideo else { return }
            isRecordingVideo = false
            UIScreen.main.brightness = CGFloat(0.01)

            sensorManager.stop() // no longer need to collect locatin/accel data

            // Invalidate the timer
            videoTimer?.invalidate()
            videoTimer = nil

            videoStartTime = nil
            videoDirectoryURL = nil

            print("Stopped video recording.")
        }
    
    
}




func writeDepthMapToTIFFWithLibTIFF(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    
    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        return false
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
    
    guard let rasters = TIFFRasters(width: Int32(width), andHeight: Int32(height), andSamplesPerPixel: 1, andSingleBitsPerSample: 32) else {
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        return false
    }
    
    for y in 0..<height {
        let pixelBytes = baseAddress.advanced(by: y * bytesPerRow)
        let pixelBuffer = UnsafeBufferPointer<Float>(start: pixelBytes.assumingMemoryBound(to: Float.self), count: width)
        for x in 0..<width {
            rasters.setFirstPixelSampleAtX(Int32(x), andY: Int32(y), withValue: NSDecimalNumber(value: pixelBuffer[x]))
        }
    }
    
    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    
    let rowsPerStrip = UInt16(rasters.calculateRowsPerStrip(withPlanarConfiguration: Int32(TIFF_PLANAR_CONFIGURATION_CHUNKY)))
    
    guard let directory = TIFFFileDirectory() else {
        return false
    }
    directory.setImageWidth(UInt16(width))
    directory.setImageHeight(UInt16(height))
    directory.setBitsPerSampleAsSingleValue(32)
    directory.setCompression(UInt16(TIFF_COMPRESSION_NO))
    directory.setPhotometricInterpretation(UInt16(TIFF_PHOTOMETRIC_INTERPRETATION_BLACK_IS_ZERO))
    directory.setSamplesPerPixel(1)
    directory.setRowsPerStrip(rowsPerStrip)
    directory.setPlanarConfiguration(UInt16(TIFF_PLANAR_CONFIGURATION_CHUNKY))
    directory.setSampleFormatAsSingleValue(UInt16(TIFF_SAMPLE_FORMAT_FLOAT))
    directory.writeRasters = rasters
    
    guard let tiffImage = TIFFImage() else {
        return false
    }
    tiffImage.addFileDirectory(directory)
    
    TIFFWriter.writeTiff(withFile: url.path, andImage: tiffImage)
    
    return true
}

func saveImage(image: CVPixelBuffer, url: URL) {
    let ciImage = CIImage(cvPixelBuffer: image)
    let context = CIContext()
    if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
       let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) {
        do {
            try jpegData.write(to: url)
        } catch {
            print("Failed to save image: \(error)")
        }
    }
}

import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import simd

enum PostProcessorError : Error {
    case missingModelMetadata
    case colorConversionError
}

struct ClosestPoint {
    let dist:Float
    let point:CGPoint
}

struct LabelAttributes : Identifiable {
    let id = UUID()          // Unique identifier
    let classId: Int
    let name: String
    let color: UIColor
    let closestpt: ClosestPoint
}

struct Metadata: Codable {
    let Accelerometer: AccelerometerData
    let Location: LocationData
    let Timestamp: Double
    let CameraIntrinsics: Matrix3x3
}

