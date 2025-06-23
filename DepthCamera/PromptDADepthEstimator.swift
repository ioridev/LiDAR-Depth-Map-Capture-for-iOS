import CoreML
import Vision
import UIKit
import CoreGraphics
import OnnxRuntimeBindings
import Accelerate

class PromptDADepthEstimator {
    private var ortSession: ORTSession?
    private var ortEnv: ORTEnv?
    private let modelSize = CGSize(width: 256, height: 192) // PromptDA model input size
    private let context = CIContext()
    private let sessionQueue = DispatchQueue(label: "promptda.session.queue")
    private var sessionInitialized = false
    
    init() {
        // Defer ONNX Runtime initialization to avoid main thread warning
        print("PromptDADepthEstimator: Creating instance, will initialize session on first use")
        print("PromptDADepthEstimator: Initial lastProcessedTimestamp = \(lastProcessedTimestamp)")
    }
    
    private func initializeSessionIfNeeded() throws {
        guard !sessionInitialized else { return }
        
        // Initialize ONNX Runtime environment
        ortEnv = try ORTEnv(loggingLevel: .warning)
        
        // Load model
        guard let modelPath = Bundle.main.path(forResource: "model_fp16", ofType: "onnx") else {
            throw NSError(domain: "PromptDADepthEstimator", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "model_fp16.onnx not found in bundle"])
        }
        
        // Create session options with CoreML execution provider
        let sessionOptions = try ORTSessionOptions()
        let coreMLOptions = ORTCoreMLExecutionProviderOptions()
        coreMLOptions.enableOnSubgraphs = true
        // onlyEnableDeviceWithANE is not available in this version
        try sessionOptions.appendCoreMLExecutionProvider(with: coreMLOptions)
        
        // Create session
        guard let env = ortEnv else {
            throw NSError(domain: "PromptDADepthEstimator", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to initialize ONNX Runtime environment"])
        }
        ortSession = try ORTSession(env: env, modelPath: modelPath, sessionOptions: sessionOptions)
        sessionInitialized = true
        
        // Debug: Print input and output names
        if let session = ortSession {
            let inputNames = try session.inputNames()
            let outputNames = try session.outputNames()
            print("PromptDADepthEstimator: Model input names: \(inputNames)")
            print("PromptDADepthEstimator: Model output names: \(outputNames)")
        }
        
        print("PromptDADepthEstimator session initialized with model at: \(modelPath)")
    }
    
    func estimateDepth(from rgbImage: CVPixelBuffer, lidarDepth: CVPixelBuffer?, resizeToOriginal: Bool = false) -> CVPixelBuffer? {
        // Initialize session on background queue if needed
        if !sessionInitialized {
            do {
                try sessionQueue.sync {
                    try initializeSessionIfNeeded()
                }
            } catch {
                print("PromptDADepthEstimator: Failed to initialize session: \(error)")
                return nil
            }
        }
        
        guard let session = ortSession else {
            print("PromptDADepthEstimator: Session not initialized")
            return nil
        }
        
        do {
            // Prepare RGB input
            let rgbTensor = try prepareRGBInput(rgbImage)
            
            // Prepare LiDAR prompt
            let lidarTensor = try prepareLiDARInput(lidarDepth)
            
            // Run inference with correct input names
            let inputs: [String: ORTValue] = [
                "pixel_values": rgbTensor,
                "prompt_depth": lidarTensor
            ]
            
            // First, get output names from the session
            let outputNames = try session.outputNames()
            print("PromptDADepthEstimator: Available output names: \(outputNames)")
            
            // Run inference - the API returns outputs automatically
            let outputs = try session.run(withInputs: inputs,
                                         outputNames: Set(outputNames),
                                         runOptions: nil)
            
            // Debug: Print output names
            print("PromptDADepthEstimator: Output names: \(outputs.keys)")
            
            // Get the first output (usually the depth map)
            guard let depthOutput = outputs.values.first else {
                print("PromptDADepthEstimator: No output from model")
                return nil
            }
            
            // Convert output to CVPixelBuffer
            let depthBuffer = try convertToPixelBuffer(depthOutput)
            
            // Resize to original image size if requested
            if resizeToOriginal {
                let originalSize = CGSize(width: CVPixelBufferGetWidth(rgbImage), 
                                        height: CVPixelBufferGetHeight(rgbImage))
                let outputSize = CGSize(width: CVPixelBufferGetWidth(depthBuffer),
                                      height: CVPixelBufferGetHeight(depthBuffer))
                
                if originalSize != outputSize {
                    print("PromptDADepthEstimator: Resizing output from \(outputSize) to \(originalSize)")
                    return resizeDepthBuffer(depthBuffer, to: originalSize)
                }
            }
            
            return depthBuffer
            
        } catch {
            print("PromptDADepthEstimator: Error during inference: \(error)")
            return nil
        }
    }
    
    private func prepareRGBInput(_ pixelBuffer: CVPixelBuffer) throws -> ORTValue {
        // Resize to model input size
        let resizedBuffer = resizePixelBuffer(pixelBuffer, to: modelSize)
        
        // Convert to normalized float array with shape [1, 3, 192, 256]
        let width = Int(modelSize.width)
        let height = Int(modelSize.height)
        var floatData = [Float](repeating: 0, count: 1 * 3 * height * width)
        
        CVPixelBufferLockBaseAddress(resizedBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(resizedBuffer, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(resizedBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(resizedBuffer)
        
        // ImageNet normalization constants
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]
        
        // Convert BGRA to normalized RGB
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                let b = Float(pixel[0]) / 255.0
                let g = Float(pixel[1]) / 255.0
                let r = Float(pixel[2]) / 255.0
                
                // Normalize and place in CHW format
                let idx = y * width + x
                floatData[0 * height * width + idx] = (r - mean[0]) / std[0] // R channel
                floatData[1 * height * width + idx] = (g - mean[1]) / std[1] // G channel
                floatData[2 * height * width + idx] = (b - mean[2]) / std[2] // B channel
            }
        }
        
        let tensorData = NSMutableData(bytes: &floatData, length: floatData.count * MemoryLayout<Float>.size)
        return try ORTValue(tensorData: tensorData,
                           elementType: .float,
                           shape: [NSNumber(value: 1), NSNumber(value: 3), NSNumber(value: height), NSNumber(value: width)])
    }
    
    private func prepareLiDARInput(_ lidarBuffer: CVPixelBuffer?) throws -> ORTValue {
        let width = Int(modelSize.width)
        let height = Int(modelSize.height)
        var floatData = [Float](repeating: 0, count: 1 * 1 * height * width)
        
        if let lidar = lidarBuffer {
            // Resize LiDAR depth to model size
            let resizedLidar = resizeDepthBuffer(lidar, to: modelSize)
            
            CVPixelBufferLockBaseAddress(resizedLidar, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(resizedLidar, .readOnly) }
            
            let baseAddress = CVPixelBufferGetBaseAddress(resizedLidar)!
            let lidarWidth = CVPixelBufferGetWidth(resizedLidar)
            let lidarHeight = CVPixelBufferGetHeight(resizedLidar)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(resizedLidar)
            
            // Copy depth values (assuming Float32 format)
            for y in 0..<min(height, lidarHeight) {
                let srcPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in 0..<min(width, lidarWidth) {
                    let depthValue = srcPtr[x]
                    // Keep metric depth values as-is (0 means unknown/invalid)
                    floatData[y * width + x] = depthValue
                }
            }
        }
        // If no LiDAR data, floatData remains all zeros (unknown depth)
        
        let tensorData = NSMutableData(bytes: &floatData, length: floatData.count * MemoryLayout<Float>.size)
        return try ORTValue(tensorData: tensorData,
                           elementType: .float,
                           shape: [NSNumber(value: 1), NSNumber(value: 1), NSNumber(value: height), NSNumber(value: width)])
    }
    
    private func convertToPixelBuffer(_ ortValue: ORTValue) throws -> CVPixelBuffer {
        let tensorData = try ortValue.tensorData() as NSData
        let tensorInfo = try ortValue.tensorTypeAndShapeInfo()
        let shape = tensorInfo.shape
        let shapeCount = shape.count
        let shape0 = shape.count > 0 ? Int(shape[0]) : 0
        let shape1 = shape.count > 1 ? Int(shape[1]) : 0
        let shape2 = shape.count > 2 ? Int(shape[2]) : 0
        
        print("PromptDADepthEstimator: Output tensor shape: \(shape)")
        
        // Handle different output shapes
        let height: Int
        let width: Int
        let needsTranspose: Bool
        
        if shape.count == 4 {
            // Shape is [batch, channels, height, width]
            height = Int(shape[2])
            width = Int(shape[3])
            needsTranspose = false
        } else if shape.count == 3 {
            // Shape is [batch, height, width] or [channels, height, width]
            if Int(shape[0]) == 1 {
                // [1, height, width] - PromptDA outputs [1, 182, 252]
                height = Int(shape[1])  // 182
                width = Int(shape[2])   // 252
                needsTranspose = false
            } else {
                // Assume [height, width, channels]
                height = Int(shape[0])
                width = Int(shape[1])
                needsTranspose = false
            }
        } else if shape.count == 2 {
            // Shape is [height, width]
            height = Int(shape[0])
            width = Int(shape[1])
            needsTranspose = false
        } else {
            throw NSError(domain: "PromptDADepthEstimator", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Unexpected output shape: \(shape)"])
        }
        
        print("PromptDADepthEstimator: Creating CVPixelBuffer with width=\(width), height=\(height)")
        
        // Create output pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_DepthFloat32
        ]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width, height,
                                        kCVPixelFormatType_DepthFloat32,
                                        attributes as CFDictionary,
                                        &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "PromptDADepthEstimator", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create output pixel buffer"])
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let destBaseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let srcPtr = tensorData.bytes.assumingMemoryBound(to: Float32.self)
        
        
        // Copy data row by row to handle potential padding
        for y in 0..<height {
            let destRowPtr = destBaseAddress.advanced(by: y * destBytesPerRow).assumingMemoryBound(to: Float32.self)
            let srcRowPtr = srcPtr.advanced(by: y * width)
            memcpy(destRowPtr, srcRowPtr, width * MemoryLayout<Float32>.size)
        }
        
        return buffer
    }
    
    private func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = size.width / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY = size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        var resizedBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,
                           Int(size.width), Int(size.height),
                           CVPixelBufferGetPixelFormatType(pixelBuffer),
                           nil,
                           &resizedBuffer)
        
        if let buffer = resizedBuffer {
            context.render(scaledImage, to: buffer)
        }
        
        return resizedBuffer!
    }
    
    private func resizeDepthBuffer(_ depthBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer {
        let srcWidth = CVPixelBufferGetWidth(depthBuffer)
        let srcHeight = CVPixelBufferGetHeight(depthBuffer)
        let dstWidth = Int(size.width)
        let dstHeight = Int(size.height)
        
        // Create destination buffer
        var dstBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_DepthFloat32
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault,
                           dstWidth, dstHeight,
                           kCVPixelFormatType_DepthFloat32,
                           attributes as CFDictionary,
                           &dstBuffer)
        
        guard let destBuffer = dstBuffer else { return depthBuffer }
        
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(destBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(destBuffer, [])
        }
        
        let srcPtr = CVPixelBufferGetBaseAddress(depthBuffer)!.assumingMemoryBound(to: Float32.self)
        let dstPtr = CVPixelBufferGetBaseAddress(destBuffer)!.assumingMemoryBound(to: Float32.self)
        
        // Simple nearest neighbor resize
        for y in 0..<dstHeight {
            for x in 0..<dstWidth {
                let srcX = x * srcWidth / dstWidth
                let srcY = y * srcHeight / dstHeight
                dstPtr[y * dstWidth + x] = srcPtr[srcY * srcWidth + srcX]
            }
        }
        
        return destBuffer
    }
    
    // Create confidence map (uniform high confidence)
    func createConfidenceMap(from depthMap: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        var confidenceMap: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: kCFBooleanTrue!
        ]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width, height,
                                        kCVPixelFormatType_OneComponent8,
                                        attributes as CFDictionary,
                                        &confidenceMap)
        
        guard status == kCVReturnSuccess, let buffer = confidenceMap else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        // Set all pixels to maximum confidence (255)
        for y in 0..<height {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
            memset(rowPtr, 255, width)
        }
        
        return buffer
    }
    
    // Performance optimization
    private var lastProcessedTimestamp: Double = -1 // Initialize to -1 to ensure first frame is processed
    private let processingInterval: Double = 0.5 // 2FPS for testing
    
    func shouldProcessFrame(timestamp: Double) -> Bool {
        // Always process first frame
        if lastProcessedTimestamp < 0 {
            lastProcessedTimestamp = timestamp
            print("PromptDADepthEstimator: Processing first frame!")
            return true
        }
        
        let timeDiff = timestamp - lastProcessedTimestamp
        print("PromptDADepthEstimator: timestamp=\(timestamp), lastProcessed=\(lastProcessedTimestamp), diff=\(timeDiff), interval=\(processingInterval)")
        if timeDiff >= processingInterval {
            lastProcessedTimestamp = timestamp
            print("PromptDADepthEstimator: Processing frame!")
            return true
        }
        print("PromptDADepthEstimator: Skipping frame (too soon)")
        return false
    }
}
