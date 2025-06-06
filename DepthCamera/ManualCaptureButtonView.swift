//
//  ManualCaptureButtonView.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUI


struct ManualCaptureButtonView: View {
    var body: some View {
        ZStack {
            // Outer ring with gradient
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: CaptureButton.strokeWidth
                )
                .frame(width: CaptureButton.outerDiameter,
                       height: CaptureButton.outerDiameter,
                       alignment: .center)
                .shadow(color: Color.white.opacity(0.3), radius: 5, x: 0, y: 2)
            
            // Inner circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: CaptureButton.innerDiameter,
                       height: CaptureButton.innerDiameter,
                       alignment: .center)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        .blur(radius: 1)
                )
        }
    }
}

