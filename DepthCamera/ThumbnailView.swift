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
    private let thumbnailFrameCornerRadius: CGFloat = 10.0
    private let thumbnailStrokeWidth: CGFloat = 2
    
    
    
    @ObservedObject var model: ARViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var isShowingFilePicker = false

    var body: some View {
          Button(action: {
              isShowingFilePicker = true
          }) {
              Group {
                  Image(systemName: "photo.on.rectangle")
                      .resizable()
                      .aspectRatio(contentMode: .fit)
                      .padding(16)
                      .frame(width: thumbnailFrameWidth, height: thumbnailFrameHeight)
                      .foregroundColor(.primary)
                      .overlay(
                          RoundedRectangle(cornerRadius: thumbnailFrameCornerRadius)
                              .stroke(Color.white, lineWidth: thumbnailStrokeWidth)
                      )
              }
              .onAppear {
                  // onAppear処理が必要な場合はここに記述
              }
          }
          .sheet(isPresented: $isShowingFilePicker) {
              DocumentPicker(directoryURL: getDocumentsDirectory())
          }
      }
      
      func getDocumentsDirectory() -> URL {
          let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
          return paths[0]
      }
  }
