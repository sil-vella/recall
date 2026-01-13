#!/usr/bin/env python3
"""
Detect images with black lines running through the middle (vertical or horizontal).
These indicate incorrectly cropped images that still contain grid separators.
"""

import os
from PIL import Image

def detect_black_lines(image_path):
    """Detect black lines running through the middle of an image."""
    img = Image.open(image_path)
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    pixels = img.load()
    width, height = img.size
    
    # Check for vertical black line (through center column)
    center_x = width // 2
    vertical_dark_count = 0
    vertical_total = 0
    
    # Sample center column and nearby columns
    for x in range(max(0, center_x - 2), min(width, center_x + 3)):
        for y in range(0, height, 2):  # Sample every 2 pixels
            brightness = sum(pixels[x, y]) / 3
            vertical_total += 1
            if brightness < 40:  # Dark pixel
                vertical_dark_count += 1
    
    vertical_ratio = vertical_dark_count / vertical_total if vertical_total > 0 else 0
    
    # Check for horizontal black line (through center row)
    center_y = height // 2
    horizontal_dark_count = 0
    horizontal_total = 0
    
    # Sample center row and nearby rows
    for y in range(max(0, center_y - 2), min(height, center_y + 3)):
        for x in range(0, width, 2):  # Sample every 2 pixels
            brightness = sum(pixels[x, y]) / 3
            horizontal_total += 1
            if brightness < 40:  # Dark pixel
                horizontal_dark_count += 1
    
    horizontal_ratio = horizontal_dark_count / horizontal_total if horizontal_total > 0 else 0
    
    # Threshold: if more than 60% of center line is dark, it's likely a grid separator
    has_vertical_line = vertical_ratio > 0.6
    has_horizontal_line = horizontal_ratio > 0.6
    
    return has_vertical_line, has_horizontal_line, vertical_ratio, horizontal_ratio

def scan_images():
    """Scan all images and detect those with black lines."""
    image_dir = 'individual_profiles'
    
    if not os.path.exists(image_dir):
        print(f"Directory {image_dir} not found!")
        return
    
    image_files = sorted([f for f in os.listdir(image_dir) if f.endswith('.jpg')])
    
    if not image_files:
        print("No images found!")
        return
    
    print(f"Scanning {len(image_files)} images for black lines...\n")
    
    vertical_line_images = []
    horizontal_line_images = []
    both_line_images = []
    
    for img_file in image_files:
        img_path = os.path.join(image_dir, img_file)
        has_vertical, has_horizontal, v_ratio, h_ratio = detect_black_lines(img_path)
        
        if has_vertical and has_horizontal:
            both_line_images.append((img_file, v_ratio, h_ratio))
        elif has_vertical:
            vertical_line_images.append((img_file, v_ratio, h_ratio))
        elif has_horizontal:
            horizontal_line_images.append((img_file, v_ratio, h_ratio))
    
    # Print results
    print("="*60)
    print("IMAGES WITH BLACK LINES DETECTED")
    print("="*60)
    
    if both_line_images:
        print(f"\n🔴 Images with BOTH vertical and horizontal black lines ({len(both_line_images)}):")
        for img_file, v_ratio, h_ratio in both_line_images:
            print(f"  - {img_file} (vertical: {v_ratio:.1%}, horizontal: {h_ratio:.1%})")
    
    if vertical_line_images:
        print(f"\n🔴 Images with VERTICAL black lines ({len(vertical_line_images)}):")
        for img_file, v_ratio, h_ratio in vertical_line_images:
            print(f"  - {img_file} (vertical line: {v_ratio:.1%} dark)")
    
    if horizontal_line_images:
        print(f"\n🔴 Images with HORIZONTAL black lines ({len(horizontal_line_images)}):")
        for img_file, v_ratio, h_ratio in horizontal_line_images:
            print(f"  - {img_file} (horizontal line: {h_ratio:.1%} dark)")
    
    if not vertical_line_images and not horizontal_line_images and not both_line_images:
        print("\n✅ No images with black lines detected! All images look good.")
    else:
        total_problematic = len(both_line_images) + len(vertical_line_images) + len(horizontal_line_images)
        print(f"\n📊 Summary:")
        print(f"  Total problematic images: {total_problematic}")
        print(f"  Images with both lines: {len(both_line_images)}")
        print(f"  Images with vertical lines: {len(vertical_line_images)}")
        print(f"  Images with horizontal lines: {len(horizontal_line_images)}")
        print(f"  Good images: {len(image_files) - total_problematic}")

if __name__ == '__main__':
    scan_images()
