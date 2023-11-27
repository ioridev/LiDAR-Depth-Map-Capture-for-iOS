import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices

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
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Date().timeIntervalSince1970
        let depthFileURL = documentsDir.appendingPathComponent("\(timestamp).tiff")

        // Check if the directory exists, if not, create it
        let directoryPath = depthFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryPath.path) {
            do {
                try FileManager.default.createDirectory(atPath: directoryPath.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Couldn't create directory: \(error)")
                return
            }
        }

        if !writeDepthMapToTIFF(depthMap: depthMap, url: depthFileURL) {
            print("Failed to save depth map.")
        } else {
            print("Depth map saved at \(depthFileURL)")
        }
    }
}



// Helper function to write depth map to a TIFF file
func writeDepthMapToTIFF(depthMap: CVPixelBuffer, url: URL) -> Bool {
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float32>.self)

    let imageData = NSMutableData(length: Int(width * height * 4))!
    let dstImageBuffer = imageData.mutableBytes.assumingMemoryBound(to: Float32.self)
    for i in 0 ..< width * height {
        dstImageBuffer[i] = floatBuffer[i]
    }

    CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))

    guard let imgDataProvider = CGDataProvider(data: imageData) else {
        print("Failed to create CGDataProvider.")
        return false
    }
    
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let bitmapInfo = CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.none.rawValue
    guard let cgImage = CGImage(width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 32, bytesPerRow: width * 4,
                          space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                          provider: imgDataProvider, decode: nil, shouldInterpolate: false,
                          intent: .defaultIntent) else {
        print("Failed to create CGImage.")
        return false
    }

    let imageDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeTIFF, 1, nil)!
    CGImageDestinationAddImage(imageDestination, cgImage, nil)
    if !CGImageDestinationFinalize(imageDestination) {
        print("Failed to write image to TIFF file.")
        return false
    }
    
    return true
}
