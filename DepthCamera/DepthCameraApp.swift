//
//  DepthCameraApp.swift
//  DepthCamera
//
//  Created by iori on 2023/11/27.
//

import SwiftUI
import ConnectIQ

@main
struct DepthCameraApp: App {
    @StateObject private var deviceViewModel = DeviceViewModel() // this needs to be here to parse the list of devices availabe from the user's garmin connect account
    @StateObject private var mbtViewModel = MBTViewModel() // this needs to be here to parse the list of devices availabe from the user's garmin connect asetccount

    var body: some Scene {
        WindowGroup {
            ContentView(deviceViewModel: deviceViewModel, mbtViewModel: mbtViewModel).onAppear {
                UIApplication.shared.isIdleTimerDisabled = true // Prevent screen locking
                initializeGarminConnectIQ()
                UIScreen.main.brightness = CGFloat(0.1)
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false // Re-enable screen locking
            }
            .onOpenURL { url in
                cdebug("Received URL: \(url)")
                if let query = url.query(), query.contains("ciqBundle") {
                    // need to store the list of availabe devices
                    deviceViewModel.parseDevices(from: url)
                }
            }
        }
    }
    
    private func initializeGarminConnectIQ() {
        ConnectIQ.sharedInstance()?.initialize(withUrlScheme: "mbt-dc", uiOverrideDelegate: nil)
        cdebug("showing device selection")
        ConnectIQ.sharedInstance()?.showDeviceSelection()
        cdebug("after device selection")
    }
    
}

func cdebug(_ message: String) {
    print("[cdebug] \(message)")
}
