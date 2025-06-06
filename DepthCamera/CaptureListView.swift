//
//  CaptureListView.swift
//  DepthCamera
//
//  Created by Assistant on 2025/01/07.
//

import SwiftUI

struct CaptureListView: View {
    @StateObject private var fileManager = CaptureFileManager()
    @State private var selectedCapture: CaptureItem?
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @State private var captureToDelete: CaptureItem?
    @State private var searchText = ""
    
    var filteredCaptures: [CaptureItem] {
        if searchText.isEmpty {
            return fileManager.captures
        } else {
            return fileManager.captures.filter { capture in
                capture.formattedDate.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if fileManager.isLoading {
                    ProgressView("Loading captures...")
                        .foregroundColor(.white)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if fileManager.captures.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No captures yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Take your first depth capture")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                        ], spacing: 16) {
                            ForEach(filteredCaptures) { capture in
                                CaptureItemView(
                                    capture: capture,
                                    onTap: { selectedCapture = capture },
                                    onDelete: {
                                        captureToDelete = capture
                                        showingDeleteAlert = true
                                    },
                                    onShare: {
                                        selectedCapture = capture
                                        showingShareSheet = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Captures")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search captures")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: fileManager.loadCaptures) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedCapture) { capture in
            CaptureDetailView(capture: capture)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let capture = selectedCapture {
                ShareSheet(activityItems: fileManager.shareCapture(capture))
            }
        }
        .alert("Delete Capture", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let capture = captureToDelete {
                    withAnimation {
                        fileManager.deleteCapture(capture)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this capture? This action cannot be undone.")
        }
    }
}

struct CaptureItemView: View {
    let capture: CaptureItem
    let onTap: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnail = capture.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 150)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        )
                }
                
                // Top gradient for better icon visibility
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                
                // Action buttons
                HStack {
                    Spacer()
                    Menu {
                        Button(action: onShare) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.3).blur(radius: 10))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            
            // Info section
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.formattedDate)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(capture.fileSize)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.8))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            onTap()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
        }
    }
}

struct CaptureDetailView: View {
    let capture: CaptureItem
    @Environment(\.dismiss) var dismiss
    @State private var depthImage: UIImage?
    @State private var showingDepthDetail = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // RGB画像とDepthマップを横並びで表示
                        HStack(spacing: 12) {
                            // RGB画像
                            VStack(spacing: 8) {
                                Text("RGB Image")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                if let image = UIImage(contentsOfFile: capture.imageURL.path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
                                }
                            }
                            
                            // Depthマップ
                            VStack(spacing: 8) {
                                Text("Depth Map")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                if let depthImage = depthImage {
                                    Image(uiImage: depthImage)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                        .onTapGesture {
                                            showingDepthDetail = true
                                        }
                                        .overlay(
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                        .font(.caption)
                                                        .foregroundColor(.white)
                                                        .padding(6)
                                                        .background(Color.black.opacity(0.6))
                                                        .clipShape(Circle())
                                                }
                                            }
                                            .padding(8)
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.gray.opacity(0.2))
                                        .aspectRatio(1.33, contentMode: .fit)
                                        .overlay(
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // 詳細情報
                        VStack(alignment: .leading, spacing: 12) {
                            DetailRow(icon: "calendar", title: "Date", value: capture.formattedDate)
                            DetailRow(icon: "doc.fill", title: "Size", value: capture.fileSize)
                            DetailRow(icon: "camera.fill", title: "Type", value: "Depth + RGB")
                            DetailRow(icon: "square.3.layers.3d", title: "Depth Format", value: "32-bit TIFF")
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Capture Details")
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
                loadDepthImage()
            }
            .sheet(isPresented: $showingDepthDetail) {
                DepthMapDetailView(depthURL: capture.depthURL)
            }
        }
    }
    
    private func loadDepthImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            // UIImageは直接TIFFファイルを読み込める
            if let depthImage = UIImage(contentsOfFile: capture.depthURL.path) {
                DispatchQueue.main.async {
                    self.depthImage = depthImage
                }
            }
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
        .font(.system(size: 14))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

