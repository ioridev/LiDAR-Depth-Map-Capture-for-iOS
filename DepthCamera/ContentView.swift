import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics
import tiff_ios



struct ContentView : View {
    @StateObject var arViewModel = ARViewModel()
    let previewCornerRadius: CGFloat = 15.0

    var body: some View {
        VStack {
            GeometryReader { geometry in
                             let width = geometry.size.width
                             let height = width * 4 / 3 // 4:3 aspect ratio
                             ARViewContainer(arViewModel: arViewModel)
                                 .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                                 .frame(width: width, height: height)
                         }
            Button(action: {
                arViewModel.saveDepthMap()
            }) {
                Text("Save Depth Map")
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func find4by3VideoFormat() -> ARConfiguration.VideoFormat? {
           let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
           for format in availableFormats {
               let resolution = format.imageResolution
               if resolution.width / 4 == resolution.height / 3 {
                   print("Using video format: \(format)")
                   return format
               }
           }
           return nil
       }



    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }

        configuration.frameSemantics.insert(.sceneDepth)
        if let format = find4by3VideoFormat() {
                  configuration.videoFormat = format
              } else {
                  print("No 4:3 video format is available")
              }


        arView.session.delegate = arViewModel
        arView.session.run(configuration)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

class ARViewModel: NSObject, ARSessionDelegate, ObservableObject {
    private var latestDepthMap: CVPixelBuffer?
    private var latestImage: CVPixelBuffer?

    
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestDepthMap = frame.sceneDepth?.depthMap
        latestImage = frame.capturedImage

    }
    
    func saveDepthMap() {
        guard let depthMap = latestDepthMap, let image = latestImage else {
            print("Depth map or image is not available.")
            return
        }
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Date().timeIntervalSince1970
    
        let depthFileURL = documentsDir.appendingPathComponent("\(timestamp)_depth.tiff")
        let imageFileURL = documentsDir.appendingPathComponent("\(timestamp)_image.jpg")
        
                writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)
        
        print("Depth map saved to \(depthFileURL)")
        print("Image saved to \(imageFileURL)")
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
