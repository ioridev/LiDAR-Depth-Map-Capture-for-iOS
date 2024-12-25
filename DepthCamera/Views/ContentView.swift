import SwiftUI
import ARKit
import RealityKit

import ImageIO
import MobileCoreServices
import CoreGraphics
import tiff_ios

struct ContentView : View {
    var deviceViewModel: DeviceViewModel
    var mbtViewModel: MBTViewModel
    @StateObject private var arViewModel = ARViewModel()
    
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
                    if (arViewModel.isRecordingVideo) {
                        ARViewContainer(arViewModel: arViewModel)
                            .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                            .frame(width: width, height: height)
                    }
                    Spacer()
                    CaptureButtonPanelView(deviceViewModel: deviceViewModel,  mbtViewModel: mbtViewModel, arViewModel: arViewModel, width: geometry.size.width)
                    
                }
            }
        }
        .onAppear() {
            // deviceViewModel needs to be able to tell the arViewModel to stop/start recording
            // when receiving messages from the ConnectIQ device
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
                        .frame(width: 275, height: 275)
                    Rectangle()
                        .foregroundColor(Color.red)
                        .frame(width: 240, height: 240)
                } else {
                    Circle()
                        .foregroundColor(Color.white)
                        .frame(width: 250, height: 250)
                }
            }
        }
    }
}
struct CaptureButtonPanelView: View {
    let deviceViewModel: DeviceViewModel
    let mbtViewModel: MBTViewModel
    @ObservedObject var arViewModel: ARViewModel
    var width: CGFloat
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack {
                ThumbnailView(model: arViewModel)
                Spacer()
                VideoModeButton(deviceViewModel: deviceViewModel, model: arViewModel)
                Spacer()
                MBTView(model: mbtViewModel)
            }
        }
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


