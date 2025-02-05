//
//  DETRPostProcessing.swift
//  DepthCamera
//
//  Created by Brian Toone on 1/30/25.
//
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import SwiftUI



class DETRPostProcessor {
    /// Number of raw classes, including empty ones with no labels
    let numClasses: Int

    /// Map from semantic id to class label
    let ids2Labels: [Int : String]

    init(model: MLModel) throws {
        struct ClassList: Codable {
            var labels: [String]
        }

        guard let userFields = model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String : String],
              let params = userFields["com.apple.coreml.model.preview.params"] else {
            throw PostProcessorError.missingModelMetadata
        }
        guard let jsonData = params.data(using: .utf8),
              let classList = try? JSONDecoder().decode(ClassList.self, from: jsonData) else {
            throw PostProcessorError.missingModelMetadata
        }
        let rawLabels = classList.labels

        // Filter out empty categories whose label is "--"
        let ids2Labels = Dictionary(uniqueKeysWithValues: rawLabels.enumerated().filter { $1 != "--" })

        self.numClasses = rawLabels.count
        self.ids2Labels = ids2Labels
        self.ids2Labels.sorted { $0.value < $1.value }.forEach { print("\($0.key): \($0.value)") }
    }

    func map448To1920(
      x448: Float, y448: Float
    ) -> (Float, Float) {
        let scaleX = Float(448.0 / 256.0) // 1.75
        let scaleY = Float(448.0 / 192.0) // 2.3333

        // Step 1: 448->256
        let x256 = x448 / scaleX
        let y256 = y448 / scaleY

        // Step 2: 256->1920
        let x1920 = x256 * 7.5
        let y1440 = y256 * 7.5

        return (x1920, y1440)
    }
    
    /// Computes horizontal angle (theta) and the forward-distance (adjacent side)
    /// given a pixel coordinate (x, y), camera intrinsics, and LiDAR radial distance r.
    func angleAndAdjacent(
        _ x: Float,
        _ y: Float,
        _ c_x: Float,    // principal point x
        _ c_y: Float,    // principal point y
        _ f_x: Float,    // focal length x
        _ f_y: Float,    // focal length y
        _ r: Float
    ) -> (theta: Float, adjacentSide: Float)
    {
        // 1) Horizontal angle: we only use the x-offset for theta
        let dx = x - c_x
        let theta = atan(dx / f_x) // angle in radians from optical center horizontally
        
        // 2) Compute the forward distance ("adjacent side") in 3D
        //    Step A: figure out how "tilted" the ray is in both x and y.
        //            - px, py, 1 forms the unnormalized direction vector in pinhole space.
        let px = dx / f_x
        let py = (y - c_y) / f_y
        // length of the direction vector:
        let dirLength = sqrt(px*px + py*py + 1.0)
        
        //    Step B: The actual forward distance is the radial distance
        //            divided by the length of that direction vector.
        //            This effectively yields the "Z" component if you
        //            transform (x,y,r) into camera coordinates.
        let adjacentSide = r / dirLength
        
        return (theta, adjacentSide)
    }
    
    func rotateCGImage180Degrees(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let bitsPerComponent = image.bitsPerComponent
        let bytesPerRow = image.bytesPerRow
        let colorSpace = image.colorSpace
        let bitmapInfo = image.bitmapInfo

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            print("Failed to create CGContext")
            return nil
        }

        // Move origin to center, rotate 180 degrees, and move back
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: .pi) // 180 degrees
        context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)

        // Draw the image into the transformed context
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    
    func annotateImage(
        image: CIImage,
        labels: [LabelAttributes],
        originalSize: CGSize
    ) -> CIImage? {
        
        // Use the image’s size directly.
        let size = image.extent.size
        
        // Create a bitmap CGContext at the exact image size (no scaling).
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        // Draw the base CIImage into this context.
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        
        // Unneeded on Mac app, but needed by iOS b/c origin is bottom left on iOS instead of top
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        // Prepare for drawing the “X” (using pure Core Graphics).
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(3.0)
        
        let crossSize: CGFloat = 10.0
        
        // Loop over points and labels.
        for label in labels {
            let point = label.closestpt.point
            
            // Draw the “X” in Core Graphics.
            context.beginPath()
            context.move(to: CGPoint(x: point.x - crossSize, y: point.y - crossSize))
            context.addLine(to: CGPoint(x: point.x + crossSize, y: point.y + crossSize))
            context.move(to: CGPoint(x: point.x - crossSize, y: point.y + crossSize))
            context.addLine(to: CGPoint(x: point.x + crossSize, y: point.y - crossSize))
            context.strokePath()
        }
        
        // Create a new image using UIGraphicsImageRenderer for text drawing.
        let renderer = UIGraphicsImageRenderer(size: size)
        let annotatedImage = renderer.image { ctx in
            // Convert CGContext
            let uiContext = ctx.cgContext
            
            // Draw the original image first
//            let rotcgImage = rotateCGImage180Degrees(context.makeImage()!)

            uiContext.draw(context.makeImage()!, in: CGRect(origin: .zero, size: size))
            
            // Loop over labels to draw text
            for label in labels {
                let point = label.closestpt.point
                let labelname = label.name
                
                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.black
                ]
                
                let roundedDist = String(format: "%.3f", label.closestpt.dist)
                
                // Define text rectangles
                let textRect = CGRect(x: point.x - crossSize, y: size.height-(point.y + crossSize), width: 100, height: 20)
                let textRect2 = CGRect(x: point.x + crossSize, y: size.height-(point.y - crossSize), width: 100, height: 20)
                
                // Draw text
                NSString(string: labelname).draw(in: textRect, withAttributes: textAttributes)
                NSString(string: "\(roundedDist)").draw(in: textRect2, withAttributes: textAttributes)
            }
        }
        
        // Convert back to CIImage
        guard let finalCGImage = annotatedImage.cgImage else {
            return nil
        }
        
        let finalCIImage = CIImage(cgImage: finalCGImage).cropped(to: CGRect(origin: .zero, size: originalSize))
        
        return finalCIImage
    }

    /// Creates a new CIImage from a raw semantic predictions returned by the model
    func semanticImage(semanticPredictions: MLShapedArray<Int32>, depthMap: [Float], minDepth:Float, maxDepth:Float, origImage: CIImage) throws -> CIImage {
        guard let image = try SemanticMapToImage.shared?.mapToImage(semanticMap: semanticPredictions, depthMap: depthMap, minDepth:minDepth, maxDepth:maxDepth, numClasses: numClasses, origImage: origImage) else {
            throw PostProcessorError.colorConversionError
        }
        return image
    }
    

    // Function to convert hue to RGB using AppKit's NSColor
    func hueToRGB(_ hue: Float) -> UIColor {
        let r = max(0, min(1, abs(hue * 6.0 - 3.0) - 1.0))
        let g = max(0, min(1, 2.0 - abs(hue * 6.0 - 2.0)))
        let b = max(0, min(1, 2.0 - abs(hue * 6.0 - 4.0)))
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
    }
    
    
    //
    //    // Iterate over the bounding box pixels
    //    for row in y..<(y + height) {
    //        for col in x..<(x + width) {
    //            // Calculate the pixel index in the data array
    //            let pixelIndex = (row * cgImage.width + col) * 4 // Assuming 4 bytes per pixel (RGBA)
    //
    //            // Extract depth value (assuming depth map is grayscale, so just one channel)
    //            let depthValue = Float(data![pixelIndex]) // Using the first channel for depth value
    //            closestDistance = min(closestDistance ?? depthValue, depthValue)
    //        }
    //    }

    // classID => count of number of pixels with that label
    func extractUniqueLabels(from semanticPredictions: MLShapedArray<Int32>) -> [Int32:Int] {
        var uniqueLabels : [Int32:Int] = [:]
        // Iterate over the array using its shape
        for i in 0..<semanticPredictions.shape[0] {
            for j in 0..<semanticPredictions.shape[1] {
                if let label = semanticPredictions[[i, j]].scalar {
                    if uniqueLabels[label] == nil {
                        uniqueLabels[label] = 1
                    } else {
                        uniqueLabels[label] = uniqueLabels[label]! + 1
                    }
                }
            }
        }
        return uniqueLabels
    }
    
    func extractUniqueLabelDists(from semanticPredictions: MLShapedArray<Int32>, depthData: DepthData, metadata: Metadata?) -> [Int32:ClosestPoint] {
        var uniqueLabels : [Int32:ClosestPoint] = [:]
        let allowed_classes : [Int32] = [8, 7, 1, 19, 25, 22, 18, 21, 3, 6, 9, 2, 5, 23, 112, 4, 24]

        // Iterate over the array using its shape
        for i in 0..<semanticPredictions.shape[0] {
            for j in 0..<semanticPredictions.shape[1] {
                let depthValue = depthData.depthAt(x: j, y: i) ?? .infinity // Using the first channel for depth value
                if let label = semanticPredictions[[i, j]].scalar, allowed_classes.contains(label) {
                    if uniqueLabels[label] == nil {
                        uniqueLabels[label] = ClosestPoint(dist:depthValue, point: CGPoint(x: Double(j), y: Double(semanticPredictions.shape[0]-i)))
                    } else if depthValue < uniqueLabels[label]!.dist {
                        uniqueLabels[label] = ClosestPoint(dist:depthValue, point: CGPoint(x: Double(j), y: Double(semanticPredictions.shape[0]-i)))
                    }
                }
            }
        }
        
        // Use the metadata to update the closest points based on the camera intrinsics
        var intrinsics : Matrix3x3?
        
        if let metadata {
            intrinsics = metadata.CameraIntrinsics
        } else {
            intrinsics = Matrix3x3(nil) // use default iphone pro 12 intrinsics
        }
        for label in uniqueLabels.keys {
            let x = uniqueLabels[label]?.point.x ?? 0.0
            let y = uniqueLabels[label]?.point.y ?? 0.0
            let (cX, cY, fX, fY) = intrinsics!.extractARKitIntrinsics()
            let (_, correctdist) = angleAndAdjacent(Float(x), Float(y), Float(cX), Float(cY), Float(fX), Float(fY), uniqueLabels[label]?.dist ?? 0.0)
           // let oldclosestpt = uniqueLabels[label]!
           // uniqueLabels[label] = ClosestPoint(dist:correctdist, point:oldclosestpt.point)
        }

        
        // Convert the Set to an Array
        return uniqueLabels
    }
    
    func generateLabels(semanticPredictions: MLShapedArray<Int32>) -> [LabelAttributes] {
        let uniqueLabelsArray = extractUniqueLabels(from: semanticPredictions)
        var labelAttributes = [LabelAttributes]()
        // Print the unique labels
        print("Unique labels: \(uniqueLabelsArray)")
        for (classID, pxcount) in uniqueLabelsArray {
            let hue = Float(classID) / Float(numClasses)
            let name = ids2Labels[Int(classID)] ?? ""
            labelAttributes.append(LabelAttributes(classId: Int(classID), name: name, color: hueToRGB(hue), closestpt: ClosestPoint(dist: Float(pxcount), point: CGPoint(x: Double(0), y: Double(0)))))
        }
        return labelAttributes
    }
    // Function to generate the label-to-color closest distance mapping
    // NOTE: there is currently no color coordination with closest distance on the labels ... that is chosen separately
    // This "all-in-one" funtion keeps us from having to determine unique labels multiple times or deal with passing around extra data structure
    func generateLabelAttributes(semanticPredictions: MLShapedArray<Int32>, depthData: DepthData, metadata: Metadata?) -> [LabelAttributes] {
        let uniqueLabelsArray = extractUniqueLabelDists(from: semanticPredictions, depthData: depthData, metadata: metadata)
        var labelAttributes = [LabelAttributes]()
        // Print the unique labels
        print("Unique labels: \(uniqueLabelsArray)")
        for (classID, closestpt) in uniqueLabelsArray {
            let hue = Float(classID) / Float(numClasses)
            let name = ids2Labels[Int(classID)] ?? ""
            labelAttributes.append(LabelAttributes(classId: Int(classID), name: name, color: hueToRGB(hue), closestpt: closestpt))
        }
        return labelAttributes
    }

}

