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

