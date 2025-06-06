//
//  CaptureButton.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUICore
import SwiftUI


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
    @State private var isPressed = false
    @State private var showPulse = false
    
    init(model: ARViewModel) {
        self.model = model
    }
    
    
    var body: some View {
        ZStack {
            // Pulse animation effect
            if showPulse {
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: CaptureButton.outerDiameter + 20, height: CaptureButton.outerDiameter + 20)
                    .scaleEffect(showPulse ? 1.5 : 1.0)
                    .opacity(showPulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: showPulse)
            }
            
            Button(action: {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                    showPulse = true
                }
                
                model.saveDepthMap()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showPulse = false
                }
            }, label: {
                ManualCaptureButtonView()
                    .scaleEffect(isPressed ? 0.9 : 1.0)
            })
        }
    }
}

