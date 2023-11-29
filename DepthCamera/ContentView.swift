import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics


struct ContentView : View {
    @StateObject var arViewModel = ARViewModel()

    var body: some View {
        VStack {
            ARViewContainer(arViewModel: arViewModel)
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



    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }

        configuration.frameSemantics.insert(.sceneDepth)

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
        let depthTiffFileURL = documentsDir.appendingPathComponent("\(timestamp)_depth.tiff")
        let depthBinaryFileURL = documentsDir.appendingPathComponent("\(timestamp)_depth.bin")
        let imageFileURL = documentsDir.appendingPathComponent("\(timestamp)_image.jpg")
        
        let scaledDepthMap = scaleDepthMapTo8Bit(depthMap: depthMap)
        writeDepthMapToTIFF(depthMap: scaledDepthMap, url: depthTiffFileURL)
        writeDepthMapToBinary(depthMap: depthMap, url: depthBinaryFileURL)
        saveImage(image: image, url: imageFileURL)
        
        print("Depth map saved to \(depthTiffFileURL) and \(depthBinaryFileURL)")
        print("Image saved to \(imageFileURL)")
    }
}



// Helper function to write depth map to a TIFF file
func writeDepthMapToTIFF(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    let data = CVPixelBufferGetBaseAddress(depthMap)!

    let colorSpace = CGColorSpaceCreateDeviceGray()
    let bitmapInfo = CGImageAlphaInfo.none.rawValue
    let bitmapContext = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: bitmapInfo)!
    let image = bitmapContext.makeImage()!

    let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeTIFF, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)

    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))

    return true
}
func scaleDepthMapTo8Bit(depthMap: CVPixelBuffer) -> CVPixelBuffer {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float>.self)

    var minDepth: Float = .greatestFiniteMagnitude
    var maxDepth: Float = -.greatestFiniteMagnitude
    for i in 0 ..< width * height {
        let depth = floatBuffer[i]
        if depth.isFinite {
            minDepth = min(minDepth, Float(depth))
            maxDepth = max(maxDepth, Float(depth))
        }
    }

    let scale = 255.0 / (maxDepth - minDepth)

    var byteBuffer = [UInt8](repeating: 0, count: width * height)
    for i in 0 ..< width * height {
        byteBuffer[i] = UInt8((Float(floatBuffer[i]) - minDepth) * scale)
    }

    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreateWithBytes(nil, width, height, kCVPixelFormatType_OneComponent8, &byteBuffer, width, nil, nil, nil, &pixelBuffer)
    if status != kCVReturnSuccess {
        fatalError("Error: could not create new pixel buffer")
    }

    return pixelBuffer!
}
func writeDepthMapToBinary(depthMap: CVPixelBuffer, url: URL) {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    let data = Data(bytes: CVPixelBufferGetBaseAddress(depthMap)!, count: width * height * 4)
    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))

    try? data.write(to: url)
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
