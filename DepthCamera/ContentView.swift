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
        
        GeometryReader { geometry in
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    
                    let width = geometry.size.width
                    let height = width * 4 / 3 // 4:3 aspect ratio
                    ARViewContainer(arViewModel: arViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                        .frame(width: width, height: height)
                    CaptureButtonPanelView(model: arViewModel,  width: geometry.size.width)
                    
                }
            }
        }
        .environment(\.colorScheme, .dark)
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
    @Published var lastCapture: UIImage? = nil {
        didSet {
            print("lastCapture was set.")
        }
    }
    
    
    
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
        let depthFileURL = dateDirURL.appendingPathComponent("\(timestamp)_depth.tiff")
        let imageFileURL = dateDirURL.appendingPathComponent("\(timestamp)_image.jpg")
        
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)
        
        
        
        
        
        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        
        
        DispatchQueue.main.async {
            self.lastCapture = uiImage
        }
        
        
        
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




struct CaptureButtonPanelView: View {
    @ObservedObject var model: ARViewModel
    var width: CGFloat
    @Environment(\.presentationMode) var presentationMode
    @State private var showAlert = false // State variable to control alert visibility
    
    
    
    
    
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack {
                ZStack(alignment: .topTrailing) {
                    ThumbnailView( model: model)
                        .frame(width: width / 3)
                        .padding(.horizontal)
                }
                Spacer()
            }
            HStack {
                Spacer()
                CaptureButton(model: model)
                Spacer()
            }
            HStack {
                /*
                 
                 Spacer()
                 
                 Spacer()
                 Button( action: {
                 
                 }) {
                 Text("")
                 .font(.system(size: 14)).bold()
                 
                 .foregroundColor(.white)
                 .padding()
                 .frame(width: 60 , height: 60)
                 .overlay(
                 RoundedRectangle(cornerRadius: 10)
                 .stroke(Color.white, lineWidth: 2)
                 )
                 
                 .padding(.horizontal)
                 }
                 
                 */
                
            }
        }
    }
    
    
}









struct ThumbnailView: View {
    private let thumbnailFrameWidth: CGFloat = 60.0
    private let thumbnailFrameHeight: CGFloat = 60.0
    private let thumbnailFrameCornerRadius: CGFloat = 10.0
    private let thumbnailStrokeWidth: CGFloat = 2
    
    
    
    @ObservedObject var model: ARViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Button(action: {
            
        }) {
            Group {
                if let capture = model.lastCapture {
                    ThumbnailImageView(uiImage: capture,
                                       width: thumbnailFrameWidth,
                                       height: thumbnailFrameHeight,
                                       cornerRadius: thumbnailFrameCornerRadius,
                                       strokeWidth: thumbnailStrokeWidth)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                        .frame(width: thumbnailFrameWidth, height: thumbnailFrameHeight)
                        .foregroundColor(.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: thumbnailFrameCornerRadius)
                                .stroke(Color.white, lineWidth: thumbnailStrokeWidth)
                        )
                }
            }
            .onAppear {
                print("ThumbnailView appeared")
            }
            .onChange(of: model.lastCapture) { newValue in
                print("Last capture changed to: \(String(describing: newValue))")
            }
        }
    }
}






struct ThumbnailImageView: View {
    var uiImage: UIImage
    var thumbnailFrameWidth: CGFloat
    var thumbnailFrameHeight: CGFloat
    var thumbnailFrameCornerRadius: CGFloat
    var thumbnailStrokeWidth: CGFloat
    
    init(uiImage: UIImage, width: CGFloat, height: CGFloat, cornerRadius: CGFloat,
         strokeWidth: CGFloat) {
        self.uiImage = uiImage
        self.thumbnailFrameWidth = width
        self.thumbnailFrameHeight = height
        self.thumbnailFrameCornerRadius = cornerRadius
        self.thumbnailStrokeWidth = strokeWidth
    }
    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: thumbnailFrameWidth, height: thumbnailFrameHeight)
            .cornerRadius(thumbnailFrameCornerRadius)
            .clipped()
            .overlay(RoundedRectangle(cornerRadius: thumbnailFrameCornerRadius)
                .stroke(Color.primary, lineWidth: thumbnailStrokeWidth))
            .shadow(radius: 10)
    }
}



struct CaptureButton: View {
    static let outerDiameter: CGFloat = 80
    static let strokeWidth: CGFloat = 4
    static let innerPadding: CGFloat = 10
    static let innerDiameter: CGFloat = CaptureButton.outerDiameter -
    CaptureButton.strokeWidth - CaptureButton.innerPadding
    static let rootTwoOverTwo: CGFloat = CGFloat(2.0.squareRoot() / 2.0)
    static let squareDiameter: CGFloat = CaptureButton.innerDiameter * CaptureButton.rootTwoOverTwo -
    CaptureButton.innerPadding
    
    @ObservedObject var model: ARViewModel
    
    init(model: ARViewModel) {
        self.model = model
    }
    
    
    var body: some View {
        Button(action: {
            model.saveDepthMap()
        },label: {
            
            ManualCaptureButtonView()
            
        })
    }
}



struct ManualCaptureButtonView: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: CaptureButton.strokeWidth)
                .frame(width: CaptureButton.outerDiameter,
                       height: CaptureButton.outerDiameter,
                       alignment: .center)
            Circle()
                .foregroundColor(Color.white)
                .frame(width: CaptureButton.innerDiameter,
                       height: CaptureButton.innerDiameter,
                       alignment: .center)
        }
    }
}

