//
//  DepthMapDetailView.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import SwiftUI
import CoreGraphics
import ImageIO

struct DepthMapDetailView: View {
    let depthURL: URL
    @Environment(\.dismiss) var dismiss
    @State private var depthImage: UIImage?
    @State private var tapLocation: CGPoint = .zero
    @State private var depthValue: Float?
    @State private var showCrosshair = false
    @State private var imageSize: CGSize = .zero
    @State private var depthData: [[Float]] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    if let depthImage = depthImage {
                        ZStack {
                            // Depth画像
                            Image(uiImage: depthImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .background(
                                    GeometryReader { imageGeometry in
                                        Color.clear.onAppear {
                                            imageSize = imageGeometry.size
                                        }
                                    }
                                )
                                .onTapGesture { location in
                                    tapLocation = location
                                    showCrosshair = true
                                    updateDepthValue(at: location, in: geometry.size)
                                }
                            
                            // クロスヘア表示
                            if showCrosshair {
                                CrosshairView(location: tapLocation)
                            }
                        }
                    } else {
                        ProgressView("Loading depth map...")
                            .foregroundColor(.white)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                
                // Depth値表示
                if let depth = depthValue {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("Depth Distance")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.2f m", depth))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Depth Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                loadDepthData()
            }
        }
    }
    
    private func loadDepthData() {
        DispatchQueue.global(qos: .userInitiated).async {
            // まず表示用の画像を読み込む
            if let image = UIImage(contentsOfFile: depthURL.path) {
                DispatchQueue.main.async {
                    self.depthImage = image
                }
            }
            
            // TIFFからDepthデータを読み込む
            loadDepthValuesFromTIFF()
        }
    }
    
    private func loadDepthValuesFromTIFF() {
        guard let imageSource = CGImageSourceCreateWithURL(depthURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // TIFFメタデータから深度情報を取得する試み
        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
            print("TIFF Properties: \(properties)")
        }
        
        // 簡易的な実装：グレースケール値から深度を推定
        // 実際のTIFF深度データの読み取りにはより詳細な実装が必要
        depthData = Array(repeating: Array(repeating: Float(0), count: width), count: height)
        
        // ビットマップコンテキストを作成してピクセルデータを取得
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerPixel = 1
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(data: &pixelData,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: bitsPerComponent,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // グレースケール値を深度値に変換（0-5メートルの範囲と仮定）
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let grayValue = Float(pixelData[pixelIndex]) / 255.0
                depthData[y][x] = grayValue * 5.0 // 0-5メートルの範囲にマッピング
            }
        }
    }
    
    private func updateDepthValue(at location: CGPoint, in viewSize: CGSize) {
        guard let image = depthImage,
              !depthData.isEmpty else { return }
        
        let imageAspectRatio = image.size.width / image.size.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var imageFrame: CGRect
        if imageAspectRatio > viewAspectRatio {
            // 画像の幅に合わせる
            let height = viewSize.width / imageAspectRatio
            imageFrame = CGRect(x: 0, y: (viewSize.height - height) / 2, width: viewSize.width, height: height)
        } else {
            // 画像の高さに合わせる
            let width = viewSize.height * imageAspectRatio
            imageFrame = CGRect(x: (viewSize.width - width) / 2, y: 0, width: width, height: viewSize.height)
        }
        
        // タップ位置を画像座標に変換
        let normalizedX = (location.x - imageFrame.origin.x) / imageFrame.width
        let normalizedY = (location.y - imageFrame.origin.y) / imageFrame.height
        
        // 範囲チェック
        guard normalizedX >= 0, normalizedX <= 1,
              normalizedY >= 0, normalizedY <= 1 else {
            return
        }
        
        // ピクセル座標に変換
        let pixelX = Int(normalizedX * CGFloat(depthData[0].count))
        let pixelY = Int(normalizedY * CGFloat(depthData.count))
        
        // 境界チェック
        guard pixelY < depthData.count,
              pixelX < depthData[pixelY].count else {
            return
        }
        
        depthValue = depthData[pixelY][pixelX]
    }
}

struct CrosshairView: View {
    let location: CGPoint
    
    var body: some View {
        ZStack {
            // 水平線
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 40, height: 1)
                .position(location)
            
            // 垂直線
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: 40)
                .position(location)
            
            // 中心点
            Circle()
                .fill(Color.clear)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 12, height: 12)
                .position(location)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: location)
    }
}