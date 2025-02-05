import CoreImage
import CoreML
import SwiftUI
import os

fileprivate let targetSize = CGSize(width: 448, height: 448)

extension CIImage {
    func scaled(to size: CGSize, context: CIContext) -> CIImage? {
        let scaleX = size.width / self.extent.width
        let scaleY = size.height / self.extent.height
        let scale = min(scaleX, scaleY) // Preserve aspect ratio
        
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = self
        filter.scale = Float(scale)
        
        return filter.outputImage
    }
}

func rotateImage180Degrees(_ image: CIImage) -> CIImage? {
    let transform = CGAffineTransform(rotationAngle: .pi) // 180 degrees in radians
    return image.transformed(by: transform)
}

func flipImageVertically(_ image: CIImage) -> CIImage? {
    let transform = CGAffineTransform(scaleX: 1, y: -1) // Flips only on the Y-axis
    return image.transformed(by: transform)
}

func resizeCIImageExact(_ image: CIImage, to targetSize: CGSize) -> CIImage? {
    let widthScale = targetSize.width / image.extent.width
    let heightScale = targetSize.height / image.extent.height
    
    // Use a scaling transform that forces both width and height independently
    let transform = CGAffineTransform(scaleX: widthScale, y: heightScale)
    let resizedImage = image.transformed(by: transform)

    // Crop to ensure no floating-point precision issues
    return resizedImage
}



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
       
    func performInferenceOnly(_ image: CIImage) -> (Image?, [LabelAttributes]?)? {
        guard let model, let postProcessor = postProcessor else {
            return nil
        }

        let context = CIContext()
        let imagesize = image.extent
        let w = imagesize.width
        let h = imagesize.height
        let originalSize = CGSize(width: w, height:h)
        
        guard let inputImage = resizeCIImageExact(image, to: targetSize) else {
            print("image scaling failed")
            return nil
        }
        
        // this is it! the problem isn't that the image was rotated, it was that it was rotated and ended up with negative extent. this doesn't actually change the rotation, but updates the extent ... in other words inputImage and correctedImage look identical when previewed, but correctedImage will generate the pixels into the pixelbuffer in the correct order
        let correctedImage = inputImage.transformed(by: CGAffineTransform(translationX: -inputImage.extent.origin.x,
                                                                         y: -inputImage.extent.origin.y))
        
        context.render(correctedImage, to: inputPixelBuffer)
        guard let result = try? model.prediction(image: inputPixelBuffer) else {
                print("model prediction failed")
                return nil;
            }

        let labelAttributes = postProcessor.generateLabels(semanticPredictions: result.semanticPredictionsShapedArray)
        

        // see if one of the labelAttributes requires us figuring out a distance (i.e., WAS THERE A CAR THERE OR NOT?!?!?!?!)
        if labelAttributes.isEmpty {
            return nil
        }
        print(labelAttributes)
        return (nil, labelAttributes)
        
    }
     
    func performInference(_ image: CIImage, depthURL: URL, metadata:Metadata?) -> (Image?, [LabelAttributes]?)? {
        guard let model, let postProcessor = postProcessor else {
            return nil
        }

        let context = CIContext()
        let imagesize = image.extent
        let w = imagesize.width
        let h = imagesize.height
        let originalSize = CGSize(width: w, height:h)
        
        guard let inputImage = resizeCIImageExact(image, to: targetSize) else {
            print("image scaling failed")
            return nil
        }
        
        // rotate doesn't work right, it's a shortcut that apple does to just create the extent in negative direction, doesn't actually rotate anything until you render
        // but when you render with negative extent it renders the image upside down in the pixelbuff EVEN THOUGH it is displayed right-side up in previews/Image/UIImage etc...
        let correctedImage = inputImage.transformed(by: CGAffineTransform(translationX: -inputImage.extent.origin.x,
                                                                         y: -inputImage.extent.origin.y))
        context.render(correctedImage, to: inputPixelBuffer)
        guard let result = try? model.prediction(image: inputPixelBuffer) else {
                print("model prediction failed")
                return nil;
            }

        let depthData = DepthData()
        depthData.loadDepthTIFF(url: depthURL, targetSize: targetSize)

        guard let labelAttributes = try? postProcessor.generateLabelAttributes(semanticPredictions: result.semanticPredictionsShapedArray, depthData: depthData, metadata: metadata) else {
            print("could not get labels")
        }
        
        // see if one of the labelAttributes requires us figuring out a distance (i.e., WAS THERE A CAR THERE OR NOT?!?!?!?!)
        if labelAttributes.isEmpty {
            return nil
        }
        
        // quick check to make sure SOMETHING is within 5.0m
        var proceed = false
        for labelAttribute in labelAttributes {
            if labelAttribute.closestpt.dist < 5.0 {
                proceed = true
                break
            }
        }

        print(labelAttributes)
        
        if proceed {
            let processor = SemanticMapProcessor()
            if let semanticCI = processor.semanticMapToCIImage(result.semanticPredictionsShapedArray, numClasses: 150),
               let depthCI = processor.depthMapToCIImage(depthData.depthData, width: 448, height: 448, minDepth: depthData.depthData.min() ?? 0.0, maxDepth: depthData.depthData.max() ?? 0.0),
               let blendedCI = processor.blendImages(semanticMap: semanticCI, depthMap: depthCI, original: inputImage) {
                
                if let annotatedImage = postProcessor.annotateImage(image: blendedCI, labels: labelAttributes, originalSize: originalSize) {
                    return (annotatedImage.image, labelAttributes)
                }
            }
        }
        
        return (nil, labelAttributes)
        
    }
    

}

// convenience method to create an Image from a CIImage ... ORIENTATION may be a problme for cameras oriented differently than my setup
fileprivate let ciContext = CIContext()
fileprivate extension CIImage {
    var image: Image? {
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
