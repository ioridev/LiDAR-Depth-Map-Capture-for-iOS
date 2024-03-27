# LiDAR Depth Map Capture for iOS

This iOS app is designed for professional users who need to capture full-resolution depth maps using the LiDAR scanner on their iPhone or iPad. It addresses the issue of depth maps being scaled down to 8-bit when using the standard iOS libraries, allowing you to capture and save depth maps with their original precision.

## Features

- Captures full-resolution depth maps from the LiDAR scanner
- Saves depth maps as 32-bit floating-point TIFF images
- Preserves the original depth values in meters
- Simple and intuitive user interface

## How it works

The LiDAR scanner on supported iPhone and iPad models provides depth information for each pixel in the captured image. However, when using the standard iOS libraries, this depth information is typically scaled down to 8-bit, losing much of the original precision.

This app bypasses that limitation by directly accessing the depth data from the LiDAR scanner and saving it as a 32-bit floating-point TIFF image. Each pixel in the resulting TIFF image contains a floating-point value representing the distance from the camera to that point in the scene, in meters.

For example, if a point in the scene is 5 meters away from the camera, the corresponding pixel value in the TIFF image will be 5.0. Similarly, if a point is 30 centimeters away, the pixel value will be 0.3.

## Requirements

- iPhone or iPad with a LiDAR scanner (iPhone 12 Pro, iPhone 12 Pro Max, iPhone 13 Pro, iPhone 13 Pro Max, iPad Pro 11-inch (2nd generation or later), iPad Pro 12.9-inch (4th generation or later))
- iOS 14 or later

## Installation

1. Clone this repository to your local machine.
2. Open the project in Xcode.
3. Connect your iPhone or iPad and select it as the build target.
4. Build and run the app on your device.

## Usage

1. Launch the app on your iPhone or iPad.
2. Point the camera at the scene you want to capture.
3. Tap the "Capture" button to capture a depth map.
4. The depth map will be saved to your device as a 32-bit floating-point TIFF image.

## Contributing

We welcome contributions to this project. If you find a bug or have a feature request, please open an issue on the GitHub repository. If you'd like to contribute code, please fork the repository and submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
