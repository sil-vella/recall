#!/usr/bin/env python3
"""
Randomize the images in assigned_images directory while keeping the same filenames.
This shuffles which image content is assigned to which filename.
"""

import os
import random
import shutil
import tempfile
from pathlib import Path

def randomize_images():
    """Randomize image assignments while keeping filenames the same."""
    target_dir = Path('assigned_images')
    
    if not target_dir.exists():
        print(f"Directory {target_dir} not found!")
        return
    
    # Get all image files
    image_files = sorted([f for f in target_dir.iterdir() if f.suffix == '.jpg' and f.name.startswith('img')])
    
    if not image_files:
        print("No images found!")
        return
    
    print(f"Found {len(image_files)} images to randomize\n")
    
    # Extract image numbers and sort to maintain order
    image_data = []
    for img_file in image_files:
        # Extract number from filename (e.g., img000.jpg -> 0)
        try:
            num_str = img_file.stem.replace('img', '')
            num = int(num_str)
            image_data.append((num, img_file))
        except ValueError:
            print(f"⚠️  Skipping invalid filename: {img_file.name}")
            continue
    
    # Sort by number to maintain img000.jpg, img001.jpg, etc. order
    image_data.sort(key=lambda x: x[0])
    
    # Extract just the file paths
    image_paths = [path for _, path in image_data]
    
    # Create a shuffled copy of the image paths
    shuffled_paths = image_paths.copy()
    random.shuffle(shuffled_paths)
    
    print("Randomizing image assignments...")
    print(f"  Original order: {image_paths[0].name} ... {image_paths[-1].name}")
    print(f"  Shuffled order: {shuffled_paths[0].name} ... {shuffled_paths[-1].name}\n")
    
    # Create temporary directory for the shuffle operation
    temp_dir = target_dir / '_temp_randomize'
    temp_dir.mkdir(exist_ok=True)
    
    try:
        # Step 1: Move all original images to temp with new names based on shuffled order
        print("Step 1: Moving images to temporary location with shuffled assignments...")
        temp_mappings = {}
        for i, (original_num, original_path) in enumerate(image_data):
            shuffled_path = shuffled_paths[i]
            temp_name = f"temp_{original_num:03d}.jpg"
            temp_path = temp_dir / temp_name
            # Copy the shuffled image content to temp with original number
            shutil.copy2(shuffled_path, temp_path)
            temp_mappings[original_num] = temp_path
        
        print(f"  ✅ Moved {len(temp_mappings)} images to temp\n")
        
        # Step 2: Remove original images
        print("Step 2: Removing original images...")
        for _, original_path in image_data:
            original_path.unlink()
        print(f"  ✅ Removed {len(image_data)} original images\n")
        
        # Step 3: Move shuffled images back with original filenames
        print("Step 3: Moving shuffled images back with original filenames...")
        for original_num, temp_path in temp_mappings.items():
            final_path = target_dir / f"img{original_num:03d}.jpg"
            shutil.move(temp_path, final_path)
        
        print(f"  ✅ Moved {len(temp_mappings)} shuffled images back\n")
        
    finally:
        # Clean up temporary directory
        if temp_dir.exists():
            try:
                temp_dir.rmdir()
            except:
                # If directory not empty, remove contents first
                for item in temp_dir.iterdir():
                    item.unlink()
                temp_dir.rmdir()
    
    print(f"{'='*60}")
    print(f"✅ Randomization complete!")
    print(f"{'='*60}")
    print(f"  Total images randomized: {len(image_data)}")
    print(f"  Filenames remain: img000.jpg to img{image_data[-1][0]:03d}.jpg")
    print(f"  Image content has been shuffled randomly")

if __name__ == '__main__':
    randomize_images()
