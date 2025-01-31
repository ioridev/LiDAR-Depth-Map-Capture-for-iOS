//
//  DepthImage.swift
//  MBTmacapp
//
//  Created by Brian Toone on 12/23/24.
//
import SwiftUI
import CoreGraphics

func resizeDepthMap(image: CGImage, width: Int, height: Int) -> CGImage? {
    let bitsPerComponent = image.bitsPerComponent
    let bytesPerRow = 4 * width // Assuming ARGB (32 bits per pixel)
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = image.bitmapInfo

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return nil
    }

    // Draw the image into the context
    context.interpolationQuality = .high // Use high-quality interpolation
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    return context.makeImage()
}

enum RotationAngle: Int, CaseIterable, Identifiable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    var id: Int { self.rawValue }
    var description: String {
        "\(self.rawValue)°"
    }
    
    func degrees() -> Angle {
        switch self {
            case .degrees0: return .degrees(0)
            case .degrees90: return .degrees(90)
            case .degrees180: return .degrees(180)
            case .degrees270: return .degrees(270)
        }
    }
}

class DepthData: ObservableObject {
    var depthData: [Float] = []
    var width: Int = 0
    var height: Int = 0
    var colorImageOrientation : UInt32 = 3

    func loadDepthTIFF(url: URL, targetSize: CGSize) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let origImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Failed to load depth map from \(url)")
            return
        }
        
        print("orig image dimensions: \(origImage.width), \(origImage.height)")

        guard let cgImage = resizeDepthMap(image: origImage, width: Int(targetSize.width), height: Int(targetSize.height)) else {
            print("Failed to resize depth map")
            return
        }
        
        self.width = cgImage.width
        self.height = cgImage.height
        
        print("loading depth map, width: \(width), height: \(height)")

        // Extract the depth data
        if let dataProvider = cgImage.dataProvider,
           let data = dataProvider.data {
            let ptr = CFDataGetBytePtr(data)
            let length = CFDataGetLength(data)
            let totalPixels = length / MemoryLayout<Float>.size

            if totalPixels == width * height {
                self.depthData = [Float](repeating: 0, count: totalPixels)
                _ = self.depthData.withUnsafeMutableBytes { buffer in
                    memcpy(buffer.baseAddress!, ptr, length)
                }
                rotateDepthData(orientation: colorImageOrientation)
            } else {
                print("Data length does not match width * height")
            }
        } else {
            print("Failed to get data provider")
        }
    }
    
    func rotateDepthDataByAngle(angle: RotationAngle) {
        let size = CGSize(width: width, height: height)
        var rotatedData = depthData

        switch angle {
        case .degrees0:
            // No rotation needed
            return
        case .degrees90:
            rotatedData = rotateDepthDataBy90CW(data: depthData, size: size)
            swap(&width, &height)
        case .degrees180:
            rotatedData = rotateDepthDataBy180(data: depthData, size: size)
        case .degrees270:
            rotatedData = rotateDepthDataBy90CCW(data: depthData, size: size)
            swap(&width, &height)
        }

        depthData = rotatedData
    }
    
    func rotateDepthDataBy180(data: [Float], size: CGSize) -> [Float] {
        let width = Int(size.width)
        let height = Int(size.height)
        var rotatedData = [Float](repeating: 0, count: data.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = (height - y - 1) * width + (width - x - 1)
                rotatedData[dstIndex] = data[srcIndex]
            }
        }
        
        return rotatedData
    }

    func rotateDepthDataBy90CW(data: [Float], size: CGSize) -> [Float] {
        let width = Int(size.width)
        let height = Int(size.height)
        var rotatedData = [Float](repeating: 0, count: data.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = x * height + (height - y - 1)
                rotatedData[dstIndex] = data[srcIndex]
            }
        }
        
        return rotatedData
    }

    func rotateDepthDataBy90CCW(data: [Float], size: CGSize) -> [Float] {
        let width = Int(size.width)
        let height = Int(size.height)
        var rotatedData = [Float](repeating: 0, count: data.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = (width - x - 1) * height + y
                rotatedData[dstIndex] = data[srcIndex]
            }
        }
        
        return rotatedData
    }

    func rotateDepthData(orientation: UInt32) {
        let size = CGSize(width: width, height: height)
        var rotatedData = depthData

        switch orientation {
        case 1:
            // Default orientation, do nothing
            return
        case 3:
            // 180 degrees
            rotatedData = rotateDepthDataBy180(data: depthData, size: size)
        case 6:
            // 90 degrees clockwise
            rotatedData = rotateDepthDataBy90CW(data: depthData, size: size)
            swap(&width, &height)
        case 8:
            // 90 degrees counterclockwise
            rotatedData = rotateDepthDataBy90CCW(data: depthData, size: size)
            swap(&width, &height)
        default:
            // Other orientations can be added as needed
            return
        }

        depthData = rotatedData
    }
    
    func depthAt(x: Int, y: Int) -> Float? {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return nil
        }
        let index = y * width + x
        let depth = depthData[index]
        if depth.isFinite {
            return depth
        } else {
            return nil
        }
    }
}
