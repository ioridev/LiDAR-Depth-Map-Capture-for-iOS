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
    let previewCornerRadius: CGFloat = 15.0
    
    var body: some View {
        
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 4 / 3 // 4:3 aspect ratio
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    // コントロールパネルを上部に配置
                    HStack(spacing: 0) {
                        // Depthマップ用のコントロール
                        VStack(alignment: .center) {
                            Button(action: {
                                showDepthMap.toggle()
                            }) {
                                Text("Depth")
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(
                                        Color.black.opacity(showDepthMap ? 0.8 : 0.6)
                                    )
                                    .cornerRadius(8)
                            }
                            
                            if showDepthMap, let depthImage = arViewModel.processedDepthImage {
                                Image(uiImage: depthImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width * 0.3, height: width * 0.3)
                                    .opacity(0.8)
                            }
                        }
                        
                        // Confidenceマップ用のコントロール
                        VStack(alignment: .center) {
                            Button(action: {
                                showConfidenceMap.toggle()
                            }) {
                                Text("Confidence")
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(
                                        Color.black.opacity(showConfidenceMap ? 0.8 : 0.6)
                                    )
                                    .cornerRadius(8)
                            }
                            
                            if showConfidenceMap, let confidenceImage = arViewModel.processedConfidenceImage {
                                Image(uiImage: confidenceImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width * 0.3, height: width * 0.3)
                                    .opacity(0.8)
                            }
                        }
                    }
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    // メインのARView
                    ARViewContainer(arViewModel: arViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                        .frame(width: width, height: height)
                    
                    CaptureButtonPanelView(model: arViewModel, width: geometry.size.width)
                }
            }
        }
        .environment(\.colorScheme, .dark)
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

