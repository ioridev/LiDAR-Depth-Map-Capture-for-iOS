//
//  ThumbnailView.swift
//  DepthCamera
//
//  Created by Brian Toone on 12/10/24.
//
import SwiftUI

struct MBTView: View {
    @ObservedObject var model : MBTViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var isShowingSync = false
    
    var body: some View {
        Button(action: {
            isShowingSync = true
        }) {
            Image("m3")
        }
        .sheet(isPresented: $isShowingSync) {
            Text("MBT Connection Status")
        }
    }
    
}

