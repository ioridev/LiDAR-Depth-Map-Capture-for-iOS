import SwiftUI
import ConnectIQ

var current: Float = 2

class DeviceViewModel: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate {
    @Published var devices: [IQDevice] = []
    var app: IQApp?
    var arModel: ARViewModel?

    func parseDevices(from url: URL) {
        if let parsedDevices = ConnectIQ.sharedInstance()?.parseDeviceSelectionResponse(from: url) as? [IQDevice] {
            self.devices = parsedDevices
            registerForDeviceEvents()
        }
//        var res : IQSendMessageResult  // this is only here to quickly navigate to the relevant code in the ConnectIQ swift library ... uncomment and then command+click it!
    }
    
    private func registerForDeviceEvents() {
        for device in devices {
            cdebug("registering \(device)")
            DispatchQueue.main.async {
                ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
                // let uuid = "a3421fee-d289-106a-538c-b9547ab12095"
                let uuid = "E3AC86BD-5B7E-43E0-84EC-757A4F311A7C"
                self.app = IQApp(uuid: UUID(uuidString: uuid), store: nil, device: device)
            }
        }
    }
    
    func setModel(_ model: ARViewModel) {
        self.arModel = model
    }
    
    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        // Handle the events from the device here
        cdebug("Received status changed from device: \(device) - \(status)")
        if (status == IQDeviceStatus.connected) {
            ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
        }
    }

    func receivedMessage(_ message: Any!, from app: IQApp!) {
        cdebug("Received message from device: \(message) - \(app)")
        if let arModel = arModel, let message = message as? String {
            cdebug(message)
            if message == "start" {
                cdebug("starting recording")
                arModel.startVideoRecording()
                sendMessage(arModel.isRecordingVideo ? "started" : "stopped")
            } else if message == "stop" {
                cdebug("stopping recording")
                arModel.stopVideoRecording()
                sendMessage(arModel.isRecordingVideo ? "started" : "stopped")
            } else if message == "status" {
                sendMessage(arModel.isRecordingVideo ? "started" : "stopped")
            }
        }
    }
    
    public func sendMessage(_ message: String) -> Void{
        if let app = app {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ConnectIQ.sharedInstance().sendMessage(message, to: app) { x, y in
                    cdebug("Sending...")
                    cdebug("\(x)")
                    cdebug("\(y)")
                } completion: { res in
                    cdebug("Sent!")
                    cdebug("\(res)")
                }
            }
        }
    }
}
