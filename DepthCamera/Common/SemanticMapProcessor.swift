import CoreImage
import UIKit
import CoreML

fileprivate let targetSize = CGSize(width: 448, height: 448)

class SemanticMapProcessor {
    let context = CIContext()
    let allowed_classes : [Int32] = [8, 7, 1, 19, 25, 22, 18, 21, 3, 6, 9, 2, 5, 23, 112, 4, 24]

    /// Converts the semantic map (MLShapedArray<Int32>) into a colorized `CIImage`
    func semanticMapToCIImage(_ semanticMap: MLShapedArray<Int32>, numClasses: Int) -> CIImage? {
        let width = semanticMap.shape[0]
        let height = semanticMap.shape[1]

        var pixelData = [UInt8](repeating: 0, count: width * height * 4) // RGBA
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let classID = semanticMap[x, y].scalar ?? 0 // Get class ID
                let hue = allowed_classes.contains(classID) ? CGFloat(classID) / CGFloat(numClasses) : 1
                let color = hueToRGB(hue) // Convert hue to RGB
                
                pixelData[index] = UInt8(color.r * 255) // Red
                pixelData[index + 1] = UInt8(color.g * 255) // Green
                pixelData[index + 2] = UInt8(color.b * 255) // Blue
                pixelData[index + 3] = 150 // Alpha
            }
        }

        return ciImageFromRGBA(pixelData, width: width, height: height)
    }

    /// Converts depth map ([Float]) into a colorized depth map `CIImage`
    func depthMapToCIImage(_ depthMap: [Float], width: Int, height: Int, minDepth: Float, maxDepth: Float) -> CIImage? {
        var pixelData = [UInt8](repeating: 0, count: width * height * 4) // RGBA

        for i in 0..<depthMap.count {
            let normalized = (depthMap[i] - minDepth) / (maxDepth - minDepth)
            let color = colorForValue(normalized) // Map to depth color

            let index = i * 4
            pixelData[index] = UInt8(color.r * 255)
            pixelData[index + 1] = UInt8(color.g * 255)
            pixelData[index + 2] = UInt8(color.b * 255)
            pixelData[index + 3] = 255
        }

        return ciImageFromRGBA(pixelData, width: width, height: height)
    }

    func resizeCIImage(_ image: CIImage, width: Int, height: Int) -> CIImage {
        let scaleX = CGFloat(width) / image.extent.width
        let scaleY = CGFloat(height) / image.extent.height
        let scale = min(scaleX, scaleY) // Maintain aspect ratio

        let transform = CIFilter.lanczosScaleTransform()
        transform.inputImage = image
        transform.scale = Float(scale)

        return transform.outputImage ?? image
    }
    
    func forceResizeCIImage(_ image: CIImage, width: Int, height: Int) -> CIImage {
        return image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                                                       y: CGFloat(height) / image.extent.height))
    }

    func forceAlignAndResize(_ image: CIImage, width: Int, height: Int) -> CIImage {
        let translated = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        return translated.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func overlayBlendMode(inputImage: CIImage, backgroundImage: CIImage) -> CIImage? {
        let colorBlendFilter = CIFilter.overlayBlendMode()
        colorBlendFilter.inputImage = inputImage
        colorBlendFilter.backgroundImage = backgroundImage
        return colorBlendFilter.outputImage
    }
    
    /// Blends the depth and semantic maps with the original image based on allowed classes
    func blendImages(semanticMap: CIImage, depthMap: CIImage, original: CIImage) -> CIImage? {
        let resizedOriginal = forceResizeCIImage(original, width: Int(targetSize.width), height: Int(targetSize.height))
        let alignedoriginal = forceAlignAndResize(resizedOriginal, width: Int(targetSize.width), height: Int(targetSize.height))
        let alignedsemantic = forceAlignAndResize(semanticMap, width: Int(targetSize.width), height: Int(targetSize.height))
        let aligneddepth = forceAlignAndResize(depthMap, width: Int(targetSize.width), height: Int(targetSize.height))

        // Step 1: Blend Depth Map over Original Image
        guard let depthBlended = overlayBlendMode(inputImage: aligneddepth, backgroundImage: alignedoriginal) else { return nil }

        // Step 2: Blend Semantic Map on top
        guard let semanticBlend = overlayBlendMode(inputImage: alignedsemantic, backgroundImage: depthBlended) else { return nil }

        return semanticBlend
    }

    /// Creates a CIImage from an RGBA byte array
    private func ciImageFromRGBA(_ data: [UInt8], width: Int, height: Int) -> CIImage? {
        let dataProvider = CGDataProvider(data: Data(data) as CFData)!
        let cgImage = CGImage(width: width, height: height,
                              bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!

        return CIImage(cgImage: cgImage)
    }

    /// Converts a hue value to an RGB color
    private func hueToRGB(_ hue: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let r = abs(hue * 6.0 - 3.0) - 1.0
        let g = 2.0 - abs(hue * 6.0 - 2.0)
        let b = 2.0 - abs(hue * 6.0 - 4.0)
        return (r: max(0, min(r, 1)), g: max(0, min(g, 1)), b: max(0, min(b, 1)))
    }

    /// Generates a depth color for a normalized value (0 to 1)
    private func colorForValue(_ normalized: Float) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let hue = 0.66 * CGFloat(clamp(normalized, 0.0, 1.0))
        return hueToRGB(hue)
    }

    /// Clamps a value between min and max
    private func clamp<T: Comparable>(_ value: T, _ minVal: T, _ maxVal: T) -> T {
        return max(min(value, maxVal), minVal)
    }
}
