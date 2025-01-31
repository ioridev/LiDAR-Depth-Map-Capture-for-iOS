import CoreImage
import CoreML
import SwiftUI
import os

fileprivate let targetSize = CGSize(width: 448, height: 448)

final class DataModel: ObservableObject {
    let context = CIContext()

    /// The segmentation  model.
    var model: DETRResnet50SemanticSegmentationF16?

    /// The sementation post-processor.
    var postProcessor: DETRPostProcessor?

    /// A pixel buffer used as input to the model.
    let inputPixelBuffer: CVPixelBuffer

    /// The last image captured from the camera.
    var lastImage = OSAllocatedUnfairLock<CIImage?>(uncheckedState: nil)

    /// The resulting segmentation image.
    @Published var segmentationImage: Image?
    
    init() {
        // Create a reusable buffer to avoid allocating memory for every model invocation
        var buffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create pixel buffer")
        }
        inputPixelBuffer = buffer
        try! loadModel()
    }
    

    func loadModel() throws {
        print("Loading model...")

        let clock = ContinuousClock()
        let start = clock.now

        model = try DETRResnet50SemanticSegmentationF16()
        if let model = model {
            postProcessor = try DETRPostProcessor(model: model.model)
        }

        let duration = clock.now - start
        print("Model loaded (took \(duration.formatted(.units(allowed: [.seconds, .milliseconds]))))")
    }

    enum InferenceError: Error {
        case postProcessing
    }

    func performInference(_ image: CIImage, depthURL: URL, metadata:Metadata?) -> (Image?, [LabelAttributes])? {
        guard let model, let postProcessor = postProcessor else {
            return nil
        }

        // load the depth data
        let depthData = DepthData()
        depthData.loadDepthTIFF(url: depthURL, targetSize: targetSize)

        let context = CIContext()
        let imagesize = image.extent
        let w = imagesize.width
        let h = imagesize.height
        let originalSize = CGSize(width: w, height:h)
        let inputImage = image.resized(to: targetSize)
        context.render(inputImage, to: inputPixelBuffer)
        guard let result = try? model.prediction(image: inputPixelBuffer) else {
                print("model prediction failed")
                return nil;
            }
        
        guard let semanticImage = try? postProcessor.semanticImage(semanticPredictions: result.semanticPredictionsShapedArray, depthMap: depthData.depthData, minDepth:depthData.depthData.min() ?? 0.0, maxDepth:depthData.depthData.max() ?? 0.0, origImage: inputImage) else {
            print("semantic image post processing failed")
            return nil
        }
        
        guard let labelAttributes = try? postProcessor.generateLabelAttributes(semanticPredictions: result.semanticPredictionsShapedArray, depthData: depthData, metadata: metadata) else {
            print("could not get labels")
        }
        // Print the mapping
        // extract the closests points
        var closestPoints : [ClosestPoint] = []
        var labels : [String] = []
        for label in labelAttributes {
            closestPoints.append(label.closestpt)
            labels.append(label.name)
        }

        let annotatedImage = try? postProcessor.annotateImage(image: semanticImage, labels: labelAttributes, originalSize: originalSize)
//        let outputImage = semanticImage.resized(to: originalSize).image
        return (annotatedImage!.image, labelAttributes)
    }
    

}

fileprivate let ciContext = CIContext()
fileprivate extension CIImage {
    var image: Image? {
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
