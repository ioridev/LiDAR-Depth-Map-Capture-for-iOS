//
//  ThumbnailView.swift
//  DepthCamera
//
//  Created by Brian Toone on 12/10/24.
//
import SwiftUI

struct ThumbnailView: View {
    private let thumbnailFrameWidth: CGFloat = 60.0
    private let thumbnailFrameHeight: CGFloat = 60.0
    private let thumbnailFrameCornerRadius: CGFloat = 10.0
    private let thumbnailStrokeWidth: CGFloat = 2
    
    @ObservedObject var model: ARViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var isShowingFilePicker = false
    @State private var hasPickedFile = false
    @State private var hardCodedFiles = false
    @State private var selectedFile: URL? = nil
    
   
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
        }
        .sheet(isPresented: $hasPickedFile) {
            let uiImage = UIImage(contentsOfFile: selectedFile!.path)!
            VStack {
                Image(uiImage: uiImage)
                    .resizable().scaledToFit().frame(minWidth: 100, maxWidth: 500, minHeight: 100, maxHeight: 500)
                    .onAppear(){
                        // start performing inference
                        model.manualInference(image: uiImage, imageURL: selectedFile!.absoluteURL)
                    }
                
                if let semanticImage = model.lastSemanticImage {
                    semanticImage
                        .resizable().scaledToFit().frame(minWidth: 100, maxWidth: 500, minHeight: 100, maxHeight: 500)
                } else {
                    Text("Performing inference...")
                }

                Button("Dismiss") {
                    hasPickedFile = false
                    selectedFile = nil
                }
            }
        }
        // this is MUCH easier to use than the older documentpicker
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let fileurl):
                selectedFile = fileurl
                hasPickedFile = true
            case .failure(let error):
                print(error)
            }
        }
        
    }
}

struct ImageProcessingView: View {
    @State var model : ARViewModel
    
    let imageNames = ["upsidedown", "rightsideup"] // Must be in Assets.xcassets
    
    @State private var ciImages: [CIImage] = []
    @State private var cgImages: [CGImage] = []
    
    var body: some View {
        HStack {
            ForEach(imageNames, id: \.self) { imageName in
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
            }
        }
        .onAppear {
            loadImages()
        }
    }
    
    func loadImages() {
        var loadedCIImages: [CIImage] = []
        
        for imageName in imageNames {
            if let uiImage = UIImage(named: imageName) {
                if let ciImage = CIImage(image: uiImage) {
                    loadedCIImages.append(ciImage)
                    model.manualInferenceOnly(image: uiImage)
                }
            }
        }
        // Update State
        ciImages = loadedCIImages
        
        print("CIImages Loaded: \(ciImages.count)")
    }
}



struct ThumbnailImageView: View {
    var uiImage: UIImage
    var thumbnailFrameWidth: CGFloat
    var thumbnailFrameHeight: CGFloat
    var thumbnailFrameCornerRadius: CGFloat
    var thumbnailStrokeWidth: CGFloat
    
    init(uiImage: UIImage, width: CGFloat, height: CGFloat, cornerRadius: CGFloat,
         strokeWidth: CGFloat) {
        self.uiImage = uiImage
        self.thumbnailFrameWidth = width
        self.thumbnailFrameHeight = height
        self.thumbnailFrameCornerRadius = cornerRadius
        self.thumbnailStrokeWidth = strokeWidth
    }
    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: thumbnailFrameWidth, height: thumbnailFrameHeight)
            .cornerRadius(thumbnailFrameCornerRadius)
            .clipped()
            .overlay(RoundedRectangle(cornerRadius: thumbnailFrameCornerRadius)
                .stroke(Color.primary, lineWidth: thumbnailStrokeWidth))
            .shadow(radius: 10)
    }
}
