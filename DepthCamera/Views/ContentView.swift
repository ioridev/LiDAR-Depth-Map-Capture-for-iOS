import ARKit
import CoreGraphics
import ImageIO
import MobileCoreServices
import RealityKit
import SwiftUI
import tiff_ios

struct ContentView: View {
    
    // most of the models ... DataModel not here b/c it's used by ARViewModel only
    // these other models have a lot of interdependencies
    //  - radarViewModel needs to tell ARViewModel to start recording
    //  - ARViewModel needs to communicate with Garmin to feed it data (deviceViewModel)
    //  - and with mybiketraffic website to broadcast live traffic data (MBTViewModel)
    var deviceViewModel: DeviceViewModel // these two models are initialized in App so we can start the connection to ConnectIQ and MBT oauth before anything is displayed
    var mbtViewModel: MBTViewModel
    @StateObject private var arViewModel = ARViewModel()
    @StateObject private var radarViewModel = RadarViewModel()
    
    @State private var buttonText: String = "Reconnect"
    @State private var isLongPressing: Bool = false
        
    var body: some View {
        
        GeometryReader { geometry in
            ZStack {
                // Make the entire background black.
                Color.black.edgesIgnoringSafeArea(.all)
                VStack {
                    
                    let width = geometry.size.width / 9  // trying to save battery ... don't even really need to see the preview ... hopefully making it much smaller will help
                    let height = width * 4 / 3  // 4:3 aspect ratio
                    if arViewModel.isRecordingVideo {
                        ARViewContainer(arViewModel: arViewModel)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 15.0)
                            )
                            .frame(width: width, height: height)
                    }
                    Spacer()

                    // Hold most recently assesse semantic image here
                    if let lastSemanticImage = arViewModel.lastSemanticImage {
                        lastSemanticImage
                            .resizable().frame(minWidth: 100, maxWidth: 500, minHeight: 100, maxHeight: 500)
                    }

                    // scrollable lazy vstack so this can grow to many tens of thousands of rows if not hundreds of thousands during a long ride
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(radarViewModel.dataRecords, id: \.id) { record in
                                HStack {
                                    Text(record.raw)
                                        .frame(width: 100, alignment: .leading)
                                        .padding(.horizontal, 5)
                                    Divider() // two column like layout
                                    Text(record.interpreted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 5)
                                }
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .frame(height: 13)
                            }
                        }
                    }
                    .frame(height: 200)
                    .border(Color.gray, width: 1)
                    .padding(.horizontal)
                    
                    // Radar status area
                    HStack {
                        VStack {
                            Text(
                                radarViewModel.isBluetoothAvailable
                                ? "Bluetooth Available" : "Bluetooth Unavailable"
                            ).foregroundColor(
                                radarViewModel.isBluetoothAvailable ? .green : .red)
                            Text(
                                radarViewModel.isRadarConnected
                                ? "Radar Connected" : "Radar Disconnected"
                            )
                            .foregroundColor(
                                radarViewModel.isRadarConnected ? .green : .red)
                        }
                        Button(action: {
                            if !isLongPressing {
                                radarViewModel.reconnectToSavedPeripheral()
                            }
                        }) {
                            Text(buttonText)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(isLongPressing ? Color.orange : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 1.0)
                                .onChanged { _ in
                                    isLongPressing = true
                                    buttonText = "Scanning for Devices..." // Change text during long press
                                }
                                .onEnded { _ in
                                    isLongPressing = false
                                    buttonText = "Reconnect" // Reset text after long press
                                    radarViewModel.scanForDevices() // Trigger scanning
                                }
                        )
                    }
                    .disabled(radarViewModel.isScanning)
                    
                    
                    CaptureButtonPanelView(
                        deviceViewModel: deviceViewModel,
                        mbtViewModel: mbtViewModel, arViewModel: arViewModel,
                        width: geometry.size.width)
                    
                }
            }
        }
        .onAppear {
            // deviceViewModel needs to be able to tell the arViewModel to stop/start recording
            // radarViewModel needs to be able to tell the arViewModel to stop/start recording
            // deviceViewModel also needs to know if the radar is connected ... b/c if it is, then it does not to respond to incoming messages from the Garmin
            // when receiving messages from the ConnectIQ device
            deviceViewModel.arModel = arViewModel
            radarViewModel.arModel = arViewModel
            radarViewModel.deviceModel = deviceViewModel
            deviceViewModel.radarModel = radarViewModel
            arViewModel.deviceModel = deviceViewModel
        }
        .environment(\.colorScheme, .dark)
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel
    
    func find4by3VideoFormat() -> ARConfiguration.VideoFormat? {
        let availableFormats = ARWorldTrackingConfiguration
            .supportedVideoFormats
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
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(
            .meshWithClassification)
        {
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
                VideoModeButton(
                    deviceViewModel: deviceViewModel, model: arViewModel)
                Spacer()
                MBTView(model: mbtViewModel)
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let directoryURL: URL
    
    func makeUIViewController(context: Context)
    -> UIDocumentPickerViewController
    {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder], asCopy: false)
        picker.directoryURL = directoryURL
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    
    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController, context: Context
    ) {}
}
