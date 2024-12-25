//
//  ManualCaptureButtonView.swift
//  DepthCamera
//
//  Created by Brian Toone on 12/10/24.
//
import SwiftUI

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
