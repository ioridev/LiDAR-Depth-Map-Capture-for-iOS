import numpy as np
from PIL import Image
import sys

# Depth map size
width = 256
height = 192

# Check if binary file was provided
if len(sys.argv) < 2:
    print("Usage: python convert.py <binary_file>")
    sys.exit(1)

# Load depth map data from binary file
binary_file = sys.argv[1]
with open(binary_file, 'rb') as f:
    depth_map_data = np.fromfile(f, dtype=np.float32)

# Reshape data to 2D array
depth_map = np.reshape(depth_map_data, (height, width))


# Save depth map as 32-bit TIFF image
output_file = binary_file.replace('.bin', '.tiff')
Image.fromarray(depth_map).save(output_file, 'TIFF')

print(f"Saved TIFF image to {output_file}")