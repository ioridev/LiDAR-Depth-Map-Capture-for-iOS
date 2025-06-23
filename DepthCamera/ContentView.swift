import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics
import tiff_ios



struct ContentView : View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showDepthMap: Bool = true
    @State private var showConfidenceMap: Bool = true
    @State private var depthMapScale: CGFloat = 1.0
    @State private var confidenceMapScale: CGFloat = 1.0
    let previewCornerRadius: CGFloat = 20.0
    
    var body: some View {
        
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 4 / 3 // 4:3 aspect ratio
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    // コントロールパネルを上部に配置
                    HStack(spacing: 20) {
                        // Depthマップ用のコントロール
                        VStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showDepthMap.toggle()
                                    depthMapScale = showDepthMap ? 1.0 : 0.8
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: showDepthMap ? "cube.fill" : "cube")
                                        .font(.system(size: 16))
                                    Text("Depth")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(showDepthMap ? 
                                            LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)], 
                                                         startPoint: .topLeading, 
                                                         endPoint: .bottomTrailing) :
                                            LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], 
                                                         startPoint: .topLeading, 
                                                         endPoint: .bottomTrailing)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .shadow(color: showDepthMap ? Color.blue.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                            }
                            .scaleEffect(depthMapScale)
                            
                            if showDepthMap, let depthImage = arViewModel.processedDepthImage {
                                Image(uiImage: depthImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width * 0.25, height: width * 0.25)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(LinearGradient(colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.2)], 
                                                                 startPoint: .topLeading, 
                                                                 endPoint: .bottomTrailing), lineWidth: 2)
                                    )
                                    .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .scale.combined(with: .opacity)
                                    ))
                            }
                        }
                        
                        // PromptDA用のコントロール
                        VStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    arViewModel.usePromptDA.toggle()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: arViewModel.usePromptDA ? "brain.head.profile" : "brain")
                                        .font(.system(size: 16))
                                    Text("PromptDA")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(arViewModel.usePromptDA ? 
                                            LinearGradient(colors: [Color.purple, Color.purple.opacity(0.8)], 
                                                         startPoint: .topLeading, 
                                                         endPoint: .bottomTrailing) :
                                            LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], 
                                                         startPoint: .topLeading, 
                                                         endPoint: .bottomTrailing)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .shadow(color: arViewModel.usePromptDA ? Color.purple.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                                .scaleEffect(arViewModel.usePromptDA ? 1.0 : 0.95)
                            }
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                        
                        // Confidenceマップ用のコントロール
                        VStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showConfidenceMap.toggle()
                                    confidenceMapScale = showConfidenceMap ? 1.0 : 0.8
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: showConfidenceMap ? "shield.fill" : "shield")
                                        .font(.system(size: 16))
                                    Text("Confidence")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(showConfidenceMap ? 
                                            LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], 
                                                         startPoint: .topLeading, 
                                                         endPoint: .bottomTrailing) :
                                            LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], 
                                                         startPoint: .topLeading, 
                                                         endPoint: .bottomTrailing)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .shadow(color: showConfidenceMap ? Color.green.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                            }
                            .scaleEffect(confidenceMapScale)
                            
                            if showConfidenceMap, let confidenceImage = arViewModel.processedConfidenceImage {
                                Image(uiImage: confidenceImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width * 0.25, height: width * 0.25)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(LinearGradient(colors: [Color.green.opacity(0.6), Color.green.opacity(0.2)], 
                                                                 startPoint: .topLeading, 
                                                                 endPoint: .bottomTrailing), lineWidth: 2)
                                    )
                                    .shadow(color: Color.green.opacity(0.3), radius: 10, x: 0, y: 5)
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .scale.combined(with: .opacity)
                                    ))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                    .background(
                        LinearGradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.7), Color.clear], 
                                     startPoint: .top, 
                                     endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    )
                    
                    Spacer()
                    
                    // メインのARView
                    ARViewContainer(arViewModel: arViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: previewCornerRadius)
                                .stroke(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)], 
                                                     startPoint: .topLeading, 
                                                     endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 10)
                        .frame(width: width * 0.9, height: height * 0.9)
                        .scaleEffect(0.95)
                    
                    // Success indicator overlay - centered checkmark
                    if arViewModel.captureSuccessful {
                        ZStack {
                            // Background blur effect
                            Color.white.opacity(0.2)
                                .ignoresSafeArea()
                                .blur(radius: 50)
                                .transition(.opacity)
                            
                            // Checkmark animation
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 80, weight: .light))
                                .foregroundColor(Color.green)
                                .shadow(color: Color.green.opacity(0.5), radius: 20, x: 0, y: 0)
                                .scaleEffect(arViewModel.captureSuccessful ? 1.0 : 0.5)
                                .opacity(arViewModel.captureSuccessful ? 1.0 : 0.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: arViewModel.captureSuccessful)
                        }
                        .allowsHitTesting(false)
                    }
                    
                    CaptureButtonPanelView(model: arViewModel, width: geometry.size.width)
                        .padding(.bottom, 30)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}


func writeDepthMapTo16BitPNG(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
    
    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
        return false
    }
    
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
    
    // Create 16-bit grayscale image
    var pixelData = [UInt16](repeating: 0, count: width * height)
    
    // Find min/max for normalization
    var minDepth: Float = Float.greatestFiniteMagnitude
    var maxDepth: Float = -Float.greatestFiniteMagnitude
    
    for y in 0..<height {
        let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
        for x in 0..<width {
            let depth = rowPtr[x]
            if !depth.isNaN && !depth.isInfinite && depth > 0 {
                minDepth = min(minDepth, depth)
                maxDepth = max(maxDepth, depth)
            }
        }
    }
    
    // Fallback if no valid depths found
    if minDepth == Float.greatestFiniteMagnitude {
        minDepth = 0
        maxDepth = 5
    }
    
    print("Depth range: \(minDepth) - \(maxDepth) meters")
    
    // Convert to 16-bit - create a simple gradient for testing
    let useTestPattern = false // Set to true for debugging
    
    for y in 0..<height {
        if useTestPattern {
            // Test pattern: horizontal gradient
            for x in 0..<width {
                let normalizedDepth = Float(x) / Float(width)
                pixelData[y * width + x] = UInt16(normalizedDepth * 65535)
            }
        } else {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let depth = rowPtr[x]
                let normalizedDepth: Float
                
                if depth.isNaN || depth.isInfinite || depth <= 0 {
                    normalizedDepth = 0
                } else {
                    normalizedDepth = (depth - minDepth) / (maxDepth - minDepth)
                }
                
                pixelData[y * width + x] = UInt16(min(max(normalizedDepth, 0), 1) * 65535)
            }
        }
    }
    
    // Create CGImage
    let bitsPerComponent = 16
    let bitsPerPixel = 16
    let bytesPerRowOut = width * 2
    
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Big.rawValue)
    
    guard let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRowOut,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return false
    }
    
    guard let cgImage = context.makeImage() else {
        return false
    }
    
    // Save as PNG
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    
    CGImageDestinationAddImage(destination, cgImage, nil)
    return CGImageDestinationFinalize(destination)
}

func writeDepthMapToTIFFWithLibTIFF(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
    
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
        let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
        for x in 0..<width {
            let depthValue = rowPtr[x]
            rasters.setFirstPixelSampleAtX(Int32(x), andY: Int32(y), withValue: NSDecimalNumber(value: depthValue))
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

