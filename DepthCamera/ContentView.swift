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

    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestDepthMap = frame.sceneDepth?.depthMap
    }
    
    func saveDepthMap() {
        guard let depthMap = latestDepthMap else {
            print("Depth map is not available.")
            return
        }

        let scaledDepthMap = scaleDepthMapTo8Bit(depthMap: depthMap)

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Date().timeIntervalSince1970
        let tiffFileURL = documentsDir.appendingPathComponent("\(timestamp)_scaled.tiff")
        let binaryFileURL = documentsDir.appendingPathComponent("\(timestamp)_raw.bin")

        writeDepthMapToTIFF(depthMap: scaledDepthMap, url: tiffFileURL)
        writeDepthMapToBinary(depthMap: depthMap, url: binaryFileURL)

        print("Depth map saved to \(tiffFileURL) and \(binaryFileURL)")
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
