import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

extension CGAffineTransform {
  static func flipVertical(height: CGFloat) -> Self {
    CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
  }
}
class SemanticMapToImage {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState

    public static let shared: SemanticMapToImage? = SemanticMapToImage()

    enum MetalConversionError : Error {
        case commandBufferError
        case encoderError
        case coreImageError
    }

    public init?() {
        guard let theMetalDevice = MTLCreateSystemDefaultDevice() else { return nil }
        device = theMetalDevice

        guard let cmdQueue = theMetalDevice.makeCommandQueue() else { return nil }
        commandQueue = cmdQueue

        guard let library = device.makeDefaultLibrary() else {
            return nil
        }

        guard let makeContiguousKernel = library.makeFunction(name: "SemanticMapToColor") else {
            return nil
        }

        guard let pipelineState = try? device.makeComputePipelineState(function: makeContiguousKernel) else {
            return nil
        }
        self.pipelineState = pipelineState
    }

    public func mapToImage(semanticMap: MLShapedArray<Int32>, depthMap: [Float], minDepth: Float, maxDepth: Float, numClasses: Int, origImage: CIImage) throws -> CIImage {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw MetalConversionError.commandBufferError
        }
        guard let outputTexture = encodeComputePipeline(commandBuffer: commandBuffer, semanticMap: semanticMap, depthMap: depthMap, minDepth: minDepth, maxDepth: maxDepth, numClasses: numClasses, origImage: origImage) else {
            throw MetalConversionError.encoderError
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let image = CIImage(mtlTexture: outputTexture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            throw MetalConversionError.coreImageError
        }
        return image
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: image.extent.height))
    }

    func encodeComputePipeline(commandBuffer: MTLCommandBuffer, semanticMap: MLShapedArray<Int32>, depthMap: [Float], minDepth: Float, maxDepth: Float, numClasses: Int, origImage: CIImage) -> MTLTexture? {
        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        commandEncoder.setComputePipelineState(pipelineState)

        let (width, height) = (semanticMap.shape[0], semanticMap.shape[1])
        let flippedImage = origImage.transformed(by: CGAffineTransform.flipVertical(height: CGFloat(height)))
        let flippedImage2 = flippedImage.transformed(by: CGAffineTransform.flipVertical(height: CGFloat(height)))
        guard let outputTexture = makeTexture(from: flippedImage2, width: width, height: height, pixelFormat: .bgra8Unorm) else { return nil }

        let (semanticTexture, depthTexture) = sourceTexture(semanticMap, depthMap)
        commandEncoder.setTexture(outputTexture, index: 2)
        commandEncoder.setTexture(depthTexture, index: 1)
        commandEncoder.setTexture(semanticTexture, index: 0)

        var classCount = numClasses
        var minDepth = minDepth
        var maxDepth = maxDepth
        commandEncoder.setBytes(&minDepth, length: MemoryLayout<Float>.size, index: 0)
        commandEncoder.setBytes(&maxDepth, length: MemoryLayout<Float>.size, index: 1)
        commandEncoder.setBytes(&classCount, length: MemoryLayout<Int32>.size, index: 2)
        
        // add the min/max depth and depthmap
        

        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSize(width: outputTexture.width,
                                     height: outputTexture.height,
                                     depth: 1)
        commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()

        return outputTexture
    }

    func sourceTexture(_ semanticMap: MLShapedArray<Int32>, _ depthMap: [Float]) -> (MTLTexture?, MTLTexture?) {
        let (width, height) = (semanticMap.shape[0], semanticMap.shape[1]) // this is WRONG, but it's a square so no worries
        let texture1 = makeTexture_origint(width: width, height: height)
        let region1 = MTLRegionMake2D(0, 0, width, height)
        let array1 = MLMultiArray(semanticMap)
        texture1?.replace(region: region1, mipmapLevel: 0, withBytes: array1.dataPointer, bytesPerRow: width * MemoryLayout<Int32>.stride)
        let texture2 = makeTexture_origfloat(width: width, height: height)
        let region2 = MTLRegionMake2D(0, 0, width, height)
        let array2 = try? MLMultiArray(depthMap)
        texture2?.replace(region: region2, mipmapLevel: 0, withBytes: array2!.dataPointer, bytesPerRow: width * MemoryLayout<Float>.stride)
        return (texture1, texture2)
    }

    func makeTexture(from ciImage: CIImage, width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        // Create the texture using your existing makeTexture function
        guard let outputTexture = makeTexture_origint(width: width, height: height, pixelFormat: pixelFormat) else {
            print("Failed to create texture")
            return nil
        }

        // Create a Core Image context with the Metal device
//        let ciContext = CIContext(mtlDevice: device)
        let ciContext = CIContext()
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        // Define the bounds of the CIImage (to match the texture size)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        
        // Render the CIImage into the Metal texture
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        ciContext.render(ciImage, to: outputTexture, commandBuffer: nil, bounds: bounds, colorSpace: colorSpace)
        return outputTexture
    }
    
    func makeTexture_origint(width: Int, height: Int, pixelFormat: MTLPixelFormat = .r32Uint) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .shared // Ensure the CPU can access the texture
        return device.makeTexture(descriptor: textureDescriptor)
    }
    func makeTexture_origfloat(width: Int, height: Int, pixelFormat: MTLPixelFormat = .r32Float) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: textureDescriptor)
    }
}
