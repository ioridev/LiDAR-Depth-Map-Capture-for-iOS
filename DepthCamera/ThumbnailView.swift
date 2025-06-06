//
//  ThumbnailView.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUICore
import SwiftUI


struct ThumbnailView: View {
    private let thumbnailFrameWidth: CGFloat = 60.0
    private let thumbnailFrameHeight: CGFloat = 60.0
    private let thumbnailFrameCornerRadius: CGFloat = 12.0
    private let thumbnailStrokeWidth: CGFloat = 2
    @State private var isPressed = false
    
    
    
    @ObservedObject var model: ARViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var isShowingFilePicker = false
    @State private var isShowingCaptureList = false

    var body: some View {
          Button(action: {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                  isPressed = true
              }
              
              let impactFeedback = UIImpactFeedbackGenerator(style: .light)
              impactFeedback.impactOccurred()
              
              isShowingCaptureList = true
              
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                      isPressed = false
                  }
              }
          }) {
              ZStack {
                  // Background with gradient
                  RoundedRectangle(cornerRadius: thumbnailFrameCornerRadius)
                      .fill(
                          LinearGradient(
                              colors: [Color.black.opacity(0.3), Color.black.opacity(0.5)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )
                      )
                      .frame(width: thumbnailFrameWidth, height: thumbnailFrameHeight)
                  
                  // Icon
                  Image(systemName: "photo.stack.fill")
                      .font(.system(size: 24))
                      .foregroundColor(.white)
                      .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                  
                  // Border overlay
                  RoundedRectangle(cornerRadius: thumbnailFrameCornerRadius)
                      .strokeBorder(
                          LinearGradient(
                              colors: [Color.white.opacity(0.8), Color.white.opacity(0.4)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          ),
                          lineWidth: thumbnailStrokeWidth
                      )
                      .frame(width: thumbnailFrameWidth, height: thumbnailFrameHeight)
              }
              .scaleEffect(isPressed ? 0.9 : 1.0)
              .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)
          }
          .sheet(isPresented: $isShowingFilePicker) {
              DocumentPicker(directoryURL: getDocumentsDirectory())
          }
          .fullScreenCover(isPresented: $isShowingCaptureList) {
              CaptureListView()
          }
      }
      
      func getDocumentsDirectory() -> URL {
          let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
          return paths[0]
      }
  }
