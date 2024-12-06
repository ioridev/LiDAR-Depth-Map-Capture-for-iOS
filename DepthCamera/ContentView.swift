import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics
import tiff_ios

struct ContentView : View {
    var deviceViewModel: DeviceViewModel
    @StateObject var arViewModel = ARViewModel()
    @State private var isVideoMode = false
    let previewCornerRadius: CGFloat = 15.0
    
    var body: some View {
        
        GeometryReader { geometry in
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    
                    let width = geometry.size.width/9 // trying to save battery ... don't even really need to see the preview ... hopefully making it much smaller will help
                    let height = width * 4 / 3 // 4:3 aspect ratio
                    ARViewContainer(arViewModel: arViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                        .frame(width: width, height: height)
                    Spacer()
                    CaptureButtonPanelView(deviceViewModel: deviceViewModel, model: arViewModel,  width: geometry.size.width)
                    
                }
            }
        }
        .onAppear() {
            deviceViewModel.setModel(arViewModel)
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
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                   configuration.frameSemantics.insert(.sceneDepth)
               }
        
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
    private var sensorManager = SensorManager()
    private var latestDepthMap: CVPixelBuffer?
    private var latestImage: CVPixelBuffer?
    
    @Published var isRecordingVideo = false
    private var videoTimer: Timer?
    private var videoStartTime: TimeInterval?
    private var videoDirectoryURL: URL?
    @Published var lastCapture: UIImage? = nil {
        didSet {
            print("lastCapture was set.")
        }
    }
    private var oddevenFrame: Int = 0
    
    
    
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
        let depthFileURL = dateDirURL.appendingPathComponent("\(timestamp)_depth\(oddevenFrame).tiff")
        let imageFileURL = dateDirURL.appendingPathComponent("\(timestamp)_image\(oddevenFrame).jpg")
        let metaFileURL = dateDirURL.appendingPathComponent("\(timestamp)_meta\(oddevenFrame).txt")
        sensorManager.saveData(textFileURL: metaFileURL, timestamp: "\(timestamp)")
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)
        oddevenFrame = (oddevenFrame + 1) % 2 // alternate between 0 and 1 ... need to mod this by 3 for 3 fps filenames

        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        
        
        DispatchQueue.main.async {
            self.lastCapture = uiImage
        }
     
        
        
        print("Depth map saved to \(depthFileURL)")
        print("Image saved to \(imageFileURL)")
    }
    
    private func captureDepthImage() {
        guard let depthMap = latestDepthMap, let image = latestImage, let videoDirURL = videoDirectoryURL else {
            print("Depth map or image is not available.")
            return
        }

        // Get current UNIX timestamp for the frame
        let frameTimestamp = Date().timeIntervalSince1970

        // File URLs for depth map and image
        let depthFileURL = videoDirURL.appendingPathComponent("\(Int(frameTimestamp))_depth\(oddevenFrame).tiff")
        let imageFileURL = videoDirURL.appendingPathComponent("\(Int(frameTimestamp))_image\(oddevenFrame).jpg")
        let metaFileURL = videoDirURL.appendingPathComponent("\(Int(frameTimestamp))_meta\(oddevenFrame).txt")
        sensorManager.saveData(textFileURL: metaFileURL, timestamp: "\(Int(frameTimestamp))")
        oddevenFrame = (oddevenFrame + 1) % 2 // alternate between 0 and 1 ... need to mod this by 3 for 3 fps filenames
    
        // Save the depth map and image
        writeDepthMapToTIFFWithLibTIFF(depthMap: depthMap, url: depthFileURL)
        saveImage(image: image, url: imageFileURL)

        // Update the last captured image for thumbnail
        let uiImage = UIImage(ciImage: CIImage(cvPixelBuffer: image))
        DispatchQueue.main.async {
            self.lastCapture = uiImage
        }

        print("Saved depth map and image at \(frameTimestamp)")
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
            videoTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
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


struct VideoModeButton: View {
    let deviceViewModel: DeviceViewModel
    @ObservedObject var model: ARViewModel

    var body: some View {
        Button(action: {
            if model.isRecordingVideo {
                model.stopVideoRecording()
                deviceViewModel.sendMessage("stopped")
            } else {
                model.startVideoRecording()
                deviceViewModel.sendMessage("started")
            }
        }) {
            ZStack {
                if model.isRecordingVideo {
                    Rectangle()
                        .foregroundColor(Color.white)
                        .frame(width: 175, height: 175)
                    Rectangle()
                        .foregroundColor(Color.red)
                        .frame(width: 150, height: 150)
                } else {
                    Circle()
                        .foregroundColor(Color.white)
                        .frame(width: 150, height: 150)
                }
            }
        }
    }
}


struct CaptureButtonPanelView: View {
    let deviceViewModel: DeviceViewModel
    @ObservedObject var model: ARViewModel
    var width: CGFloat
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack {
                ZStack(alignment: .topTrailing) {
                    ThumbnailView(model: model)
                        .frame(width: width / 3)
                        .padding(.horizontal)
                }
                Spacer()
            }
            HStack {
                Spacer()
                VideoModeButton(deviceViewModel: deviceViewModel, model: model)
                Spacer()
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
    
    @State private var isShowingFilePicker = false

    var body: some View {
          Button(action: {
              isShowingFilePicker = true
          }) {
              Group {
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
              .onAppear {
              }
          }
          .sheet(isPresented: $isShowingFilePicker) {
              DocumentPicker(directoryURL: getDocumentsDirectory())
          }
      }
      
      func getDocumentsDirectory() -> URL {
          let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
          return paths[0]
      }
  }

  struct DocumentPicker: UIViewControllerRepresentable {
      let directoryURL: URL
      
      func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
          let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
          picker.directoryURL = directoryURL
          picker.modalPresentationStyle = .fullScreen
          return picker
      }
      
      func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
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
    static let outerDiameter: CGFloat = 160
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

