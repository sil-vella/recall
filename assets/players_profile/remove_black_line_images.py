#!/usr/bin/env python3
"""
Scan assigned_images directory and remove images that contain only black lines
or are essentially empty/black images.
"""

import os
from PIL import Image

def is_mostly_black_line(image_path, threshold=0.85):
    """Check if an image is mostly just a black line or empty."""
    try:
        img = Image.open(image_path)
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        pixels = img.load()
        width, height = img.size
        
        # Count dark pixels (brightness < 40)
        dark_pixels = 0
        total_pixels = width * height
        
        for y in range(height):
            for x in range(width):
                r, g, b = pixels[x, y]
                brightness = (r + g + b) / 3
                if brightness < 40:
                    dark_pixels += 1
        
        # If more than threshold% of pixels are dark, it's likely just a black line/empty
        dark_ratio = dark_pixels / total_pixels
        
        # Also check if there's a clear vertical or horizontal line through the center
        center_x = width // 2
        center_y = height // 2
        
        # Check center column
        center_col_dark = 0
        for y in range(height):
            r, g, b = pixels[center_x, y]
            if (r + g + b) / 3 < 40:
                center_col_dark += 1
        
        # Check center row
        center_row_dark = 0
        for x in range(width):
            r, g, b = pixels[x, center_y]
            if (r + g + b) / 3 < 40:
                center_row_dark += 1
        
        center_col_ratio = center_col_dark / height if height > 0 else 0
        center_row_ratio = center_row_dark / width if width > 0 else 0
        
        # Image is problematic if:
        # 1. More than threshold% of pixels are dark (mostly black)
        # 2. Center line is mostly dark (>90%) AND overall image is mostly dark (>70%)
        is_mostly_black = dark_ratio > threshold
        has_center_line = (center_col_ratio > 0.9 or center_row_ratio > 0.9) and dark_ratio > 0.7
        
        return is_mostly_black or has_center_line, dark_ratio, center_col_ratio, center_row_ratio
        
    except Exception as e:
        print(f"  ⚠️  Error processing {image_path}: {e}")
        return False, 0, 0, 0

def scan_and_remove_black_line_images():
    """Scan all images in assigned_images and remove those that are mostly black lines."""
    target_dir = 'assigned_images'
    
    if not os.path.exists(target_dir):
        print(f"Directory {target_dir} not found!")
        return
    
    image_files = sorted([f for f in os.listdir(target_dir) if f.endswith('.jpg')])
    
    if not image_files:
        print("No images found!")
        return
    
    print(f"Scanning {len(image_files)} images for black line images...\n")
    
    problematic_images = []
    
    for img_file in image_files:
        img_path = os.path.join(target_dir, img_file)
        is_black, dark_ratio, col_ratio, row_ratio = is_mostly_black_line(img_path)
        
        if is_black:
            problematic_images.append((img_file, dark_ratio, col_ratio, row_ratio))
    
    if not problematic_images:
        print("✅ No black line images found! All images look good.")
        return
    
    print(f"\n{'='*60}")
    print(f"BLACK LINE IMAGES DETECTED: {len(problematic_images)}")
    print(f"{'='*60}\n")
    
    for img_file, dark_ratio, col_ratio, row_ratio in problematic_images:
        print(f"  🔴 {img_file}")
        print(f"     Dark pixels: {dark_ratio:.1%}, Center col: {col_ratio:.1%}, Center row: {row_ratio:.1%}")
    
    print(f"\n{'='*60}")
    print(f"Removing {len(problematic_images)} black line images...")
    print(f"{'='*60}\n")
    
    removed = 0
    failed = 0
    
    for img_file, _, _, _ in problematic_images:
        img_path = os.path.join(target_dir, img_file)
        try:
            os.remove(img_path)
            removed += 1
            print(f"  ✅ Removed: {img_file}")
        except Exception as e:
            print(f"  ❌ Failed to remove {img_file}: {e}")
            failed += 1
    
    print(f"\n{'='*60}")
    print(f"✅ Complete!")
    print(f"{'='*60}")
    print(f"  Images removed: {removed}")
    print(f"  Failed: {failed}")
    print(f"  Remaining images: {len(image_files) - removed}")

if __name__ == '__main__':
    scan_and_remove_black_line_images()
