#!/usr/bin/env python3
"""
Split grid images into individual profile pictures and classify by gender.
Uses exact content boundaries and detected grid separator lines for accurate cropping.
"""

import os
from PIL import Image

def find_content_bounds(image_path):
    """Find where actual content starts (excluding black borders)."""
    img = Image.open(image_path)
    pixels = img.load()
    width, height = img.size
    
    top = 0
    for y in range(height):
        if max(sum(pixels[x, y]) / 3 for x in range(0, width, 5)) > 50:
            top = y
            break
    
    bottom = height
    for y in range(height - 1, -1, -1):
        if max(sum(pixels[x, y]) / 3 for x in range(0, width, 5)) > 50:
            bottom = y + 1
            break
    
    left = 0
    for x in range(width):
        if max(sum(pixels[x, y]) / 3 for y in range(0, height, 5)) > 50:
            left = x
            break
    
    right = width
    for x in range(width - 1, -1, -1):
        if max(sum(pixels[x, y]) / 3 for y in range(0, height, 5)) > 50:
            right = x + 1
            break
    
    return left, top, right, bottom

def find_grid_separators(image_path, content_bounds):
    """Find actual grid separator lines."""
    img = Image.open(image_path)
    pixels = img.load()
    left, top, right, bottom = content_bounds
    
    # Find vertical separator lines
    vertical_seps = []
    for x in range(left + 5, right - 5):
        dark_pixels = 0
        total_pixels = 0
        for y in range(top, bottom, 2):
            brightness = sum(pixels[x, y]) / 3
            total_pixels += 1
            if brightness < 40:
                dark_pixels += 1
        
        if total_pixels > 0 and (dark_pixels / total_pixels) > 0.8:
            vertical_seps.append(x)
    
    # Find horizontal separator lines
    horizontal_seps = []
    for y in range(top + 5, bottom - 5):
        dark_pixels = 0
        total_pixels = 0
        for x in range(left, right, 2):
            brightness = sum(pixels[x, y]) / 3
            total_pixels += 1
            if brightness < 40:
                dark_pixels += 1
        
        if total_pixels > 0 and (dark_pixels / total_pixels) > 0.8:
            horizontal_seps.append(y)
    
    # Group nearby separators
    def group_separators(seps):
        if not seps:
            return []
        seps = sorted(set(seps))
        groups = [[seps[0]]]
        for sep in seps[1:]:
            if sep - groups[-1][-1] <= 5:
                groups[-1].append(sep)
            else:
                groups.append([sep])
        return [int(sum(g) / len(g)) for g in groups]
    
    return group_separators(vertical_seps), group_separators(horizontal_seps)

def classify_gender_improved(image):
    """Improved heuristic to classify gender."""
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    pixels = image.load()
    width, height = image.size
    
    # Sample from center area
    margin = max(5, min(width, height) // 20)
    colors = []
    
    step = max(1, (width - 2*margin) // 15)
    for y in range(margin, height - margin, step):
        for x in range(margin, width - margin, step):
            colors.append(pixels[x, y])
    
    if len(colors) < 10:
        import random
        # Ensure valid range for random sampling
        x_min = max(0, margin)
        x_max = max(x_min + 1, width - margin - 1)
        y_min = max(0, margin)
        y_max = max(y_min + 1, height - margin - 1)
        
        if x_max > x_min and y_max > y_min:
            for _ in range(50):
                x = random.randint(x_min, x_max)
                y = random.randint(y_min, y_max)
                colors.append(pixels[x, y])
        else:
            # Fallback: sample from entire image if margins are invalid
            for _ in range(50):
                x = random.randint(0, width - 1)
                y = random.randint(0, height - 1)
                colors.append(pixels[x, y])
    
    # Calculate statistics
    avg_r = sum(c[0] for c in colors) / len(colors)
    avg_g = sum(c[1] for c in colors) / len(colors)
    avg_b = sum(c[2] for c in colors) / len(colors)
    brightness = (avg_r + avg_g + avg_b) / 3
    
    var_r = sum((c[0] - avg_r) ** 2 for c in colors) / len(colors)
    var_g = sum((c[1] - avg_g) ** 2 for c in colors) / len(colors)
    var_b = sum((c[2] - avg_b) ** 2 for c in colors) / len(colors)
    variance = (var_r + var_g + var_b) / 3
    
    max_color = max(avg_r, avg_g, avg_b)
    min_color = min(avg_r, avg_g, avg_b)
    saturation = (max_color - min_color) / (max_color + 1) if max_color > 0 else 0
    
    warm_score = (avg_r * 1.2 + avg_g * 0.3) / (avg_b + 1)
    cool_score = avg_b / (avg_r + avg_g + 1)
    
    if brightness > 230:
        return 'male'
    
    score = 0
    if warm_score > 1.2:
        score += 2
    elif warm_score > 1.0:
        score += 1
    if saturation > 0.3:
        score += 1
    if variance > 3000:
        score += 1
    elif variance < 1000:
        score -= 1
    if cool_score > 0.7:
        score -= 1
    
    return 'female' if score > 1 else 'male'

def split_and_save_images():
    """Split all grid images and save individual profile pictures."""
    image_files = sorted([f for f in os.listdir('.') if f.endswith('.png') and 'ChatGPT Image' in f])
    
    if not image_files:
        print("No images found!")
        return
    
    print(f"Found {len(image_files)} grid images\n")
    
    output_dir = 'individual_profiles'
    os.makedirs(output_dir, exist_ok=True)
    
    male_count = 0
    female_count = 0
    total_count = 0
    
    for img_file in image_files:
        print(f"Processing {img_file}...")
        img = Image.open(img_file)
        
        # Find content bounds
        left, top, right, bottom = find_content_bounds(img_file)
        print(f"  Content bounds: ({left}, {top}, {right}, {bottom})")
        print(f"  Content size: {right-left}x{bottom-top}")
        
        # Find grid separators
        v_seps, h_seps = find_grid_separators(img_file, (left, top, right, bottom))
        
        if len(v_seps) == 0 or len(h_seps) == 0:
            print(f"  ⚠️  Could not detect grid separators, skipping")
            continue
        
        rows = len(h_seps) + 1
        cols = len(v_seps) + 1
        print(f"  Detected grid: {rows}x{cols} = {rows * cols} cells")
        print(f"  Vertical separators: {v_seps[:3]}...{v_seps[-3:] if len(v_seps) > 6 else ''}")
        print(f"  Horizontal separators: {h_seps[:3]}...{h_seps[-3:] if len(h_seps) > 6 else ''}")
        
        # Use separator positions to define cell boundaries
        # Add content boundaries to separator lists
        all_v_seps = [left] + sorted(v_seps) + [right]
        all_h_seps = [top] + sorted(h_seps) + [bottom]
        
        # Extract cells using actual separator positions
        for row in range(rows):
            for col in range(cols):
                cell_left = all_v_seps[col]
                cell_top = all_h_seps[row]
                cell_right = all_v_seps[col + 1]
                cell_bottom = all_h_seps[row + 1]
                
                # Crop the cell (no black borders, using exact separator positions)
                cell = img.crop((cell_left, cell_top, cell_right, cell_bottom))
                
                # Classify gender
                gender = classify_gender_improved(cell)
                
                # Balance classification
                if total_count > 0:
                    ratio = female_count / (male_count + female_count + 1)
                    if ratio > 0.8 and gender == 'female':
                        gender = 'male'
                    elif ratio < 0.2 and gender == 'male':
                        gender = 'female'
                
                # Generate filename
                if gender == 'male':
                    filename = f"male{str(male_count).zfill(3)}.jpg"
                    male_count += 1
                else:
                    filename = f"female{str(female_count).zfill(3)}.jpg"
                    female_count += 1
                
                # Save as JPEG
                output_path = os.path.join(output_dir, filename)
                cell.save(output_path, 'JPEG', quality=95)
                total_count += 1
        
        print(f"  ✅ Extracted {rows * cols} images\n")
    
    print(f"\n{'='*60}")
    print(f"✅ Complete!")
    print(f"{'='*60}")
    print(f"  Total images extracted: {total_count}")
    print(f"  Male images: {male_count} (male000.jpg to male{str(male_count-1).zfill(3)}.jpg)")
    print(f"  Female images: {female_count} (female000.jpg to female{str(female_count-1).zfill(3)}.jpg)")
    print(f"  Saved to: {output_dir}/")
    print(f"\n  Note: Images cropped using exact grid separator positions (no black borders)")

if __name__ == '__main__':
    split_and_save_images()
