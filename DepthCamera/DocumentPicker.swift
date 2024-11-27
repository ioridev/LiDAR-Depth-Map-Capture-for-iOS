//
//  DocumentPicker.swift
//  DepthCamera
//
//  Created by iori on 2024/11/27.
//

import SwiftUI


 struct DocumentPicker: UIViewControllerRepresentable {
      let directoryURL: URL
      
      func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
          let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
          picker.directoryURL = directoryURL
          picker.modalPresentationStyle = .fullScreen
          return picker
      }
      
      func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
  }

