//
//  ARViewModel.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import ARKit


class ARViewModel: NSObject, ARSessionDelegate, ObservableObject {
    private var latestDepthMap: CVPixelBuffer?
    private var latestImage: CVPixelBuffer?
    @Published var processedDepthImage: UIImage?
    @Published var processedConfidenceImage: UIImage?
    @Published var showDepthMap: Bool = true
    @Published var showConfidenceMap: Bool = true
    @Published var captureSuccessful: Bool = false
    @Published var lastCapture: UIImage? = nil {
        didSet {
            print("lastCapture was set.")
        }
    }
    @Published var lastCaptureURL: URL?
    
    // PromptDA depth estimation
    private var depthEstimator: PromptDADepthEstimator?
    @Published var usePromptDA: Bool = true
    
    private var lastDepthUpdate: TimeInterval = 0
    private let depthUpdateInterval: TimeInterval = 0.5 // 2fps for PromptDA preview
    
    override init() {
        super.init()
        // Initialize PromptDA
        depthEstimator = PromptDADepthEstimator()
        print("ARViewModel: PromptDA depth estimator initialized")
    }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestImage = frame.capturedImage
        let currentTime = CACurrentMediaTime()
        
        if currentTime - lastDepthUpdate >= depthUpdateInterval {
            lastDepthUpdate = currentTime  // タイマーを更新
            
            // Use PromptDA for depth estimation if enabled
            if usePromptDA, let estimator = depthEstimator {
                if estimator.shouldProcessFrame(timestamp: frame.timestamp) {
                    print("ARViewModel: Using PromptDA for depth estimation")
                    
                    
                    // For preview, don't resize to save performance
                    if let promptDADepth = estimator.estimateDepth(from: frame.capturedImage, lidarDepth: frame.sceneDepth?.depthMap, resizeToOriginal: false) {
                        latestDepthMap = promptDADepth
                        print("ARViewModel: PromptDA depth estimation successful")
                        processDepthMap(promptDADepth)
                        
                        // Also create confidence map from PromptDA
                        if showConfidenceMap, let confMap = estimator.createConfidenceMap(from: promptDADepth) {
                            processConfidenceMap(confMap)
                        }
                    } else {
                        print("ARViewModel: PromptDA depth estimation failed, falling back to ARKit depth")
                        // Fall back to ARKit depth
                        latestDepthMap = frame.sceneDepth?.depthMap
                        if showDepthMap, let depthMap = frame.sceneDepth?.depthMap {
                            processDepthMap(depthMap)
                        }
                        if showConfidenceMap, let confidenceMap = frame.sceneDepth?.confidenceMap {
                            processConfidenceMap(confidenceMap)
                        }
                    }
                } else {
                    // Not time to process with PromptDA, use ARKit depth
                    latestDepthMap = frame.sceneDepth?.depthMap
                    if showDepthMap, let depthMap = frame.sceneDepth?.depthMap {
                        processDepthMap(depthMap)
                    }
                    if showConfidenceMap, let confidenceMap = frame.sceneDepth?.confidenceMap {
                        processConfidenceMap(confidenceMap)
                    }
                }
            } else {
                // PromptDA disabled or not initialized, use ARKit depth
                latestDepthMap = frame.sceneDepth?.depthMap
                if showDepthMap, let depthMap = frame.sceneDepth?.depthMap {
                    processDepthMap(depthMap)
                }
                if showConfidenceMap, let confidenceMap = frame.sceneDepth?.confidenceMap {
                    processConfidenceMap(confidenceMap)
                }
            }
        }
    }
    
    func saveDepthMap() {
        // Simply use the current latestDepthMap that was used for preview
        guard let depthMap = latestDepthMap, let image = latestImage else {
            print("Depth map or image is not available.")
            return
        }
        
        // デバッグ: 保存するdepthMapのサイズを確認
        let saveWidth = CVPixelBufferGetWidth(depthMap)
        let saveHeight = CVPixelBufferGetHeight(depthMap)
        let saveBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        print("Saving depth map: \(saveWidth)x\(saveHeight), bytesPerRow=\(saveBytesPerRow)")
        
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
        
        let timestamp = Date().timeIntervalSince1970
        let depthFileURL = dateDirURL.appendingPathComponent("\(timestamp)_depth.png")
        let depthTiffURL = dateDirURL.appendingPathComponent("\(timestamp)_depth.tiff")
        let imageFileURL = dateDirURL.appendingPathComponent("\(timestamp)_image.jpg")
        
        // Save as both PNG and TIFF for comparison
        writeDepthMapTo16BitPNG(depthMap: depthMap, url: depthFileURL)
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthTiffURL)
        saveImage(image: image, url: imageFileURL)
        
        
        
        
        
        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        
        
        DispatchQueue.main.async {
            self.lastCapture = uiImage
            self.lastCaptureURL = imageFileURL
            self.captureSuccessful = true
            
            // Reset after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.captureSuccessful = false
            }
        }
     
        
        
        print("Depth map saved to \(depthFileURL)")
        print("Depth TIFF saved to \(depthTiffURL)")
        print("Image saved to \(imageFileURL)")
    }
}



extension ARViewModel {
    func resizePixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        to size: CGSize
    ) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(
            size.width / CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )
        let scaledImage = ciImage.transformed(by: CGAffineTransform(
            scaleX: scale,
            y: scale
        ))

        let context = CIContext(options: nil)
        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &outputPixelBuffer
        )

        if let outputPixelBuffer = outputPixelBuffer {
            context.render(scaledImage, to: outputPixelBuffer)
            return outputPixelBuffer
        }
        return nil
    }
}

// DepthMapを可視化する関数を追加
extension ARViewModel {
    // DepthMapを可視化する関数
    private func processDepthMap(_ depthMap: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        var normalizedData = [UInt8](repeating: 0, count: width * height * 4)

        let buffer = CVPixelBufferGetBaseAddress(depthMap)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size
        
        for y in 0..<height {
            for x in 0..<width {
                let floatBuffer = buffer?.assumingMemoryBound(to: Float32.self)
                let depth = floatBuffer?[y * floatsPerRow + x] ?? 0
                // 深度を0-1の範囲に正規化（例：0-5メートルを想定）
                // NaNやInfiniteをチェック
                let validDepth = depth.isNaN || depth.isInfinite ? 0.0 : depth
                let normalizedDepth = min(max(validDepth / 5.0, 0.0), 1.0)
                let pixel = UInt8(normalizedDepth * 255.0)
                
                let index = (y * width + x) * 4
                normalizedData[index] = pixel     // R
                normalizedData[index + 1] = pixel // G
                normalizedData[index + 2] = pixel // B
                normalizedData[index + 3] = 255   // A
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: &normalizedData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let cgImage = context.makeImage() else { return }

        DispatchQueue.main.async { [weak self] in
            // 画像を90度回転
            let rotatedImage = UIImage(cgImage: cgImage)
                .rotate(radians: .pi/2) // 90度回転
            self?.processedDepthImage = rotatedImage
        }
    }

    // ConfidenceMapを可視化する関数
    private func processConfidenceMap(_ confidenceMap: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        var rgbaData = [UInt8](repeating: 0, count: width * height * 4)

        let buffer = CVPixelBufferGetBaseAddress(confidenceMap)?.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let confidence = buffer?[y * width + x] ?? 0
                let index = (y * width + x) * 4
                
                // 信頼度に基づいて色を設定
                switch confidence {
                case 0:  // 信頼度なし
                    rgbaData[index] = 255    // R - 赤
                    rgbaData[index + 1] = 0  // G
                    rgbaData[index + 2] = 0  // B
                case 1:  // 低信頼度
                    rgbaData[index] = 255    // R - 黄
                    rgbaData[index + 1] = 255  // G
                    rgbaData[index + 2] = 0    // B
                case 2:  // 高信頼度
                    rgbaData[index] = 0      // R - 緑
                    rgbaData[index + 1] = 255  // G
                    rgbaData[index + 2] = 0    // B
                default:  // 最高信頼度
                    rgbaData[index] = 0      // R - 青
                    rgbaData[index + 1] = 0    // G
                    rgbaData[index + 2] = 255  // B
                }
                rgbaData[index + 3] = 255   // A - 完全な不透明度
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: &rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let cgImage = context.makeImage() else { return }

        DispatchQueue.main.async { [weak self] in
            // 画像を90度回転（ARKitのconfidenceMapは回転が必要）
            let rotatedImage = UIImage(cgImage: cgImage)
                .rotate(radians: .pi/2) // 90度回転
            self?.processedConfidenceImage = rotatedImage
        }

    }
}

extension UIImage {
    func rotate(radians: Float) -> UIImage? {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size)
            .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .size
        // Trim off the extremely small float value to prevent core graphics from rounding it up
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        let context = UIGraphicsGetCurrentContext()!

        // Move origin to middle
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        // Rotate around middle
        context.rotate(by: CGFloat(radians))
        // Draw the image at its center
        let rect = CGRect(
            x: -self.size.width/2,
            y: -self.size.height/2,
            width: self.size.width,
            height: self.size.height)
        
        self.draw(in: rect)

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
}

