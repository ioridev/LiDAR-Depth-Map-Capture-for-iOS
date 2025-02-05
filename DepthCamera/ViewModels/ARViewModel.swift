import SwiftUI
import ARKit
import RealityKit
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import simd
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
    
    var deviceModel: DeviceViewModel?
    private var model = DataModel() // ai model
    @Published var lastSemanticImage: Image?
    
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestDepthMap = frame.sceneDepth?.depthMap
        latestImage = frame.capturedImage
        latestFrame = frame
    }
    
    func rotateImage180Degrees(_ image: CIImage) -> CIImage? {
        let transform = CGAffineTransform(rotationAngle: .pi) // 180 degrees in radians
        return image.transformed(by: transform)
    }
    
    func rotatedPixelBuffer(from ciImage: CIImage, rotationAngle radians: CGFloat) -> CVPixelBuffer? {
        let context = CIContext()
        
        // Rotate the image properly
        let rotatedImage = ciImage.transformed(by: CGAffineTransform(rotationAngle: radians))
        
        // Get the image dimensions after rotation
        let width = Int(rotatedImage.extent.width)
        let height = Int(rotatedImage.extent.height)
        
        // Create a new pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return nil }
        
        // Lock pixel buffer and render into it
        CVPixelBufferLockBaseAddress(buffer, .init(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgContext = CGContext(data: baseAddress,
                                        width: width,
                                        height: height,
                                        bitsPerComponent: 8,
                                        bytesPerRow: bytesPerRow,
                                        space: colorSpace,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
            return nil
        }
        
        // Render CIImage into the CGContext
        let cgImage = context.createCGImage(rotatedImage, from: rotatedImage.extent)
        if let cgImage = cgImage {
            cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
        
        return buffer
    }
    
    func manualInferenceOnly(image: UIImage) {
        if let cgImage = image.cgImage {
            let ciImage = rotateImage180Degrees(CIImage(cgImage: cgImage))!
            
//            let ciImage = CIImage(cgImage: cgImage)
            if let (annnotatedImage, labelattributes) = model.performInferenceOnly(ciImage) {
                if let semanticImage = annnotatedImage  {
                    lastSemanticImage = semanticImage
                }
                print(labelattributes)
            }
        }
    }
    // manually invoke the process so we can see the heatmap on an image selected from the document directory
    func manualInference(image: UIImage, imageURL: URL) {
        
        // extract the baseurl from the imageURL so we can retrieve the depthmap
        let baseURL = imageURL.deletingLastPathComponent()
        
        // extract the frame timestamp from the filename
        let frameTimestamp = imageURL.lastPathComponent.components(separatedBy: "_").first!
        
        // File URLs for depth map and image
        let depthFileURL = baseURL.appendingPathComponent("\(Int(frameTimestamp)!)_depth.tiff")
        let imageFileURL = baseURL.appendingPathComponent("\(Int(frameTimestamp)!)_image.jpg")
        let metaFileURL = baseURL.appendingPathComponent("\(Int(frameTimestamp)!)_meta.txt")
        
        // now retrieve the depthmap
//        let depthmap = loadDepthMapFromTIFF(url: depthFileURL)
        
        // now retrieve the matadata
        let metadata = sensorManager.loadData(metadataFileURL: metaFileURL)
        
        //        guard let ciImage = rotateImage180Degrees(usdImage) else { return }
        
        if let cgImage = image.cgImage {
            let ciImage = rotateImage180Degrees(CIImage(cgImage: cgImage))!
//            let ciImage = CIImage(cgImage: cgImage)
            if let (annnotatedImage, labelattributes) = model.performInference(ciImage, depthURL: depthFileURL, metadata: metadata) {
                if let semanticImage = annnotatedImage  {
                    lastSemanticImage = semanticImage
                }
                print(labelattributes)
            }
        }
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
        
        // Save the depth map and image ... this will return false if we run out of space ... could use this to gracefully STOP trying to record and/or display some sort of OutOfMemory warning
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)
        
        let context = CIContext()
        let usdImage = CIImage(cvPixelBuffer: image)
        guard let ciImage = rotateImage180Degrees(usdImage) else { return }
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            if let (annnotatedImage, labelattributes) = model.performInference(ciImage, depthURL: depthFileURL, metadata: metadata) {
                if let semanticImage = annnotatedImage  {
                    lastSemanticImage = semanticImage
                    sendMessageIfAllowed(labelattributes) // semanticImage will be nil if there is no valid class within 5.0m
                }
            }
        }
        
        print("Saved depth map and image at \(frameTimestamp)")
    }
    
    var lastMessageTime: TimeInterval = 0
    let cooldownInterval: TimeInterval = 2 // 2 seconds cooldown

    func sendMessageIfAllowed(_ labelattributes: [LabelAttributes]?) {
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastMessageTime >= cooldownInterval {
            deviceModel?.sendMessage(labelout(labelattributes))
            lastMessageTime = currentTime
        } else {
            print("Skipping sendMessage - Cooldown active")
        }
    }
    
    func labelout(_ labelattributes: [LabelAttributes]?) -> String {
        guard let labelattributes = labelattributes, !labelattributes.isEmpty else {
            return ""
        }
        
        return labelattributes.map { "\($0.name): \($0.closestpt.dist)" }.joined(separator: "\n")
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

func loadDepthMapFromTIFF(url: URL) -> CVPixelBuffer? {
    // Read the TIFF file using fromFile instead of withFile
    guard let tiffImage = TIFFReader.readTiff(fromFile: url.path) else {
        print("Failed to read TIFF file")
        return nil
    }
    
    // Get the first file directory (assuming a single-image TIFF)
    guard let directory = tiffImage.fileDirectories().first else {
        print("Failed to get TIFF directory")
        return nil
    }
        
    // Retrieve width and height from metadata
    let width = Int(truncating: directory.imageWidth())
    let height = Int(truncating: directory.imageHeight())
    
    // Read raster data safely
    guard let rasters = directory.readRasters() else {
        print("Failed to retrieve raster data")
        return nil
    }
    
    // Create a CVPixelBuffer to hold the depth data
    var pixelBuffer: CVPixelBuffer?
    let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_OneComponent32Float
    ]
    
    let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     width,
                                     height,
                                     kCVPixelFormatType_OneComponent32Float,
                                     pixelBufferAttributes as CFDictionary,
                                     &pixelBuffer)
    
    guard status == kCVReturnSuccess, let depthMap = pixelBuffer else {
        print("Failed to create CVPixelBuffer")
        return nil
    }
    
    // Lock and populate the CVPixelBuffer
    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        return nil
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
    
    for y in 0..<height {
        let pixelBytes = baseAddress.advanced(by: y * bytesPerRow)
        let pixelBuffer = UnsafeMutableBufferPointer<Float>(start: pixelBytes.assumingMemoryBound(to: Float.self), count: width)
        for x in 0..<width {
            pixelBuffer[x] = rasters.firstPixelSampleAt(x:Int32(x), andY: Int32(y)).floatValue
        }
    }
    
    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    return depthMap
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

