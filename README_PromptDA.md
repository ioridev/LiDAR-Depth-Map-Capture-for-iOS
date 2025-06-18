# PromptDA Integration for DepthCamera

This document describes how to integrate PromptDA depth estimation into the DepthCamera project.

## Setup Instructions

### 1. Add ONNX Runtime via Swift Package Manager

1. Open `DepthCamera.xcworkspace` in Xcode
2. Go to File → Add Package Dependencies
3. Add the ONNX Runtime package:
   - URL: `https://github.com/microsoft/onnxruntime-swift-package-manager`
   - Version: 1.20.0 or latest

### 2. Add Files to Xcode Project

The following files have been added to the project:
- `PromptDADepthEstimator.swift` - The depth estimation class
- `model_fp16.onnx` - The PromptDA model file

Make sure to:
1. Add both files to the Xcode project
2. Ensure `model_fp16.onnx` is included in the app bundle (check Target Membership)

### 3. Build and Run

1. Select a real device with LiDAR (iPhone 12 Pro or later, iPad Pro with LiDAR)
2. Build and run the project
3. Use the "PromptDA" toggle button to switch between ARKit depth and PromptDA depth estimation

## Usage

The app now has three toggle buttons at the top:
- **Depth**: Show/hide depth visualization
- **PromptDA**: Enable/disable PromptDA depth estimation (purple button)
- **Confidence**: Show/hide confidence map

When PromptDA is enabled:
- The app will use the PromptDA model to estimate depth from RGB images
- LiDAR data is used as a sparse depth prompt to improve accuracy
- Processing is limited to 2 FPS to maintain performance

## Debugging

Look for these log messages:
- `ARViewModel: PromptDA depth estimator initialized`
- `ARViewModel: Using PromptDA for depth estimation`
- `ARViewModel: PromptDA depth estimation successful`
- `PromptDADepthEstimator: Model input names: [...]`
- `PromptDADepthEstimator: Processing first frame!`

## Troubleshooting

If depth estimation isn't working:
1. Check that the ONNX model file is included in the bundle
2. Look for error messages about invalid input names
3. Verify that the device has enough memory to run the model
4. Try reducing the frame rate by modifying `processingInterval` in PromptDADepthEstimator.swift