//
//  DepthCameraApp.swift
//  DepthCamera
//
//  Created by iori on 2023/11/27.
//

import SwiftUI

@main
struct DepthCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().onAppear {
                UIApplication.shared.isIdleTimerDisabled = true // Prevent screen locking
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false // Re-enable screen locking
            }
        }
    }
}
