import numpy as np
from PIL import Image
import sys
import os

# Depth map size
width = 256
height = 192

# Check if folder path was provided
if len(sys.argv) < 2:
    print("Usage: python convert.py <folder_path>")
    sys.exit(1)

# Folder path
folder_path = sys.argv[1]

# Process each .bin file in the folder
for filename in os.listdir(folder_path):
    if filename.endswith(".bin"):
        bin_file = os.path.join(folder_path, filename)

        # Load depth map data from binary file
        with open(bin_file, 'rb') as f:
            depth_map_data = np.fromfile(f, dtype=np.float32)

        # Reshape data to 2D array
        depth_map = np.reshape(depth_map_data, (height, width))

        # Save depth map as 32-bit TIFF image
        output_file = bin_file.replace('.bin', '.tiff')
        Image.fromarray(depth_map).save(output_file, 'TIFF')

        print(f"Saved TIFF image to {output_file}")
