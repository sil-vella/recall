#!/usr/bin/env python3
"""
Renumber all images in assigned_images to have sequential numbering from img000.jpg
with no gaps.
"""

import os
import re
import shutil

def renumber_images():
    """Renumber all images sequentially starting from img000.jpg."""
    target_dir = 'assigned_images'
    
    if not os.path.exists(target_dir):
        print(f"Directory {target_dir} not found!")
        return
    
    # Get all image files and extract their numbers
    image_files = []
    for f in os.listdir(target_dir):
        if f.endswith('.jpg') and f.startswith('img'):
            match = re.search(r'img(\d+)\.jpg', f)
            if match:
                img_number = int(match.group(1))
                image_files.append((img_number, f))
    
    if not image_files:
        print("No images found!")
        return
    
    # Sort by image number
    image_files.sort(key=lambda x: x[0])
    
    print(f"Found {len(image_files)} images to renumber\n")
    print(f"Current range: img{image_files[0][0]:03d}.jpg to img{image_files[-1][0]:03d}.jpg")
    print(f"Target range: img000.jpg to img{len(image_files)-1:03d}.jpg\n")
    
    # Create temporary directory for renaming
    temp_dir = os.path.join(target_dir, '_temp_renumber')
    os.makedirs(temp_dir, exist_ok=True)
    
    # First pass: move all files to temp directory with new names
    print("Step 1: Moving files to temporary location...")
    moved = 0
    for new_index, (old_number, old_filename) in enumerate(image_files):
        old_path = os.path.join(target_dir, old_filename)
        new_filename = f"img{new_index:03d}.jpg"
        temp_path = os.path.join(temp_dir, new_filename)
        
        try:
            shutil.move(old_path, temp_path)
            moved += 1
            if moved <= 10 or moved % 50 == 0:
                print(f"  ✅ {old_filename} -> {new_filename}")
        except Exception as e:
            print(f"  ❌ Error moving {old_filename}: {e}")
            return
    
    print(f"  Moved {moved} files to temporary location\n")
    
    # Second pass: move files back to target directory
    print("Step 2: Moving files back with new names...")
    moved_back = 0
    for new_index in range(len(image_files)):
        new_filename = f"img{new_index:03d}.jpg"
        temp_path = os.path.join(temp_dir, new_filename)
        final_path = os.path.join(target_dir, new_filename)
        
        try:
            shutil.move(temp_path, final_path)
            moved_back += 1
            if moved_back <= 10 or moved_back % 50 == 0:
                print(f"  ✅ {new_filename}")
        except Exception as e:
            print(f"  ❌ Error moving {new_filename}: {e}")
            return
    
    # Remove temporary directory
    try:
        os.rmdir(temp_dir)
    except:
        pass
    
    print(f"\n{'='*60}")
    print(f"✅ Complete!")
    print(f"{'='*60}")
    print(f"  Images renumbered: {moved_back}")
    print(f"  New range: img000.jpg to img{moved_back-1:03d}.jpg")
    print(f"  All images now have sequential numbering with no gaps")

if __name__ == '__main__':
    renumber_images()
