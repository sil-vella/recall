#!/usr/bin/env python3
"""
Generate Flutter App Icons from Single Source Image

This script takes a single 1024x1024 image with a solid background and logo,
and generates all required app icon images for Flutter launcher icons:
- icon.png (1024x1024) - Base icon for iOS and Android
- icon_foreground.png (432x432) - Android adaptive icon foreground (transparent background)
- icon_background.png (432x432) - Android adaptive icon background (solid color)

Then automatically:
- Updates pubspec.yaml to enable flutter_launcher_icons
- Runs flutter pub get
- Runs flutter pub run flutter_launcher_icons

Usage:
    python3 generate_app_icons.py [--source SOURCE_PATH] [--output OUTPUT_DIR] [--skip-flutter]

Requirements:
    pip install Pillow
"""

import argparse
import sys
import subprocess
import re
from pathlib import Path
from PIL import Image
import os

# Default paths
PROJECT_ROOT = Path(__file__).parent.parent.parent
DEFAULT_SOURCE = PROJECT_ROOT / 'branding' / 'images' / 'app_image.png'
DEFAULT_OUTPUT = PROJECT_ROOT / 'flutter_base_05' / 'assets' / 'images'
PUBSPEC_PATH = PROJECT_ROOT / 'flutter_base_05' / 'pubspec.yaml'
FLUTTER_DIR = PROJECT_ROOT / 'flutter_base_05'

def extract_background_color(image):
    """
    Extract the dominant background color from image corners.
    Assumes the corners contain the background color.
    """
    width, height = image.size
    corner_size = min(50, width // 10, height // 10)  # Sample from corners
    
    # Sample from all four corners
    corners = [
        image.crop((0, 0, corner_size, corner_size)),  # Top-left
        image.crop((width - corner_size, 0, width, corner_size)),  # Top-right
        image.crop((0, height - corner_size, corner_size, height)),  # Bottom-left
        image.crop((width - corner_size, height - corner_size, width, height)),  # Bottom-right
    ]
    
    # Calculate average color from corners
    total_r, total_g, total_b = 0, 0, 0
    pixel_count = 0
    
    for corner in corners:
        pixels = corner.getdata()
        for pixel in pixels:
            if len(pixel) >= 3:  # RGB or RGBA
                total_r += pixel[0]
                total_g += pixel[1]
                total_b += pixel[2]
                pixel_count += 1
    
    if pixel_count == 0:
        # Fallback to white if we can't extract color
        return (255, 255, 255)
    
    avg_r = int(total_r / pixel_count)
    avg_g = int(total_g / pixel_count)
    avg_b = int(total_b / pixel_count)
    
    return (avg_r, avg_g, avg_b)

def create_foreground_with_transparency(image, background_color, tolerance=30):
    """
    Create foreground image by making background transparent.
    Uses color similarity to determine what is background.
    """
    # Convert to RGBA if not already
    if image.mode != 'RGBA':
        image = image.convert('RGBA')
    
    # Create new image with transparency
    foreground = Image.new('RGBA', image.size, (0, 0, 0, 0))
    pixels = image.load()
    foreground_pixels = foreground.load()
    
    bg_r, bg_g, bg_b = background_color[:3]
    
    for y in range(image.height):
        for x in range(image.width):
            pixel = pixels[x, y]
            r, g, b = pixel[0], pixel[1], pixel[2]
            
            # Calculate color distance from background
            distance = ((r - bg_r) ** 2 + (g - bg_g) ** 2 + (b - bg_b) ** 2) ** 0.5
            
            if distance <= tolerance:
                # This is background - make transparent
                foreground_pixels[x, y] = (0, 0, 0, 0)
            else:
                # This is foreground - keep original with alpha
                alpha = pixel[3] if len(pixel) > 3 else 255
                foreground_pixels[x, y] = (r, g, b, alpha)
    
    return foreground

def generate_app_icons(source_path, output_dir):
    """
    Generate all required app icon images from source image.
    """
    source_path = Path(source_path)
    output_dir = Path(output_dir)
    
    # Validate source image exists
    if not source_path.exists():
        print(f"❌ Error: Source image not found: {source_path}")
        return False
    
    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"📸 Loading source image: {source_path}")
    try:
        source_image = Image.open(source_path)
    except Exception as e:
        print(f"❌ Error: Failed to load image: {e}")
        return False
    
    # Validate source image size
    if source_image.size != (1024, 1024):
        print(f"⚠️  Warning: Source image is {source_image.size}, expected 1024x1024")
        print(f"   Resizing to 1024x1024...")
        source_image = source_image.resize((1024, 1024), Image.Resampling.LANCZOS)
    
    print(f"✅ Source image loaded: {source_image.size} ({source_image.mode})")
    
    # Extract background color
    print(f"🎨 Extracting background color...")
    background_color = extract_background_color(source_image)
    print(f"   Background color: RGB{background_color}")
    
    # 1. Generate icon.png (1024x1024) - base icon
    print(f"\n📦 Generating icon.png (1024x1024)...")
    icon_path = output_dir / 'icon.png'
    # Ensure no transparency for base icon
    if source_image.mode == 'RGBA':
        # Create RGB version with white background
        rgb_image = Image.new('RGB', source_image.size, (255, 255, 255))
        rgb_image.paste(source_image, mask=source_image.split()[3] if source_image.mode == 'RGBA' else None)
        rgb_image.save(icon_path, 'PNG', optimize=True)
    else:
        source_image.convert('RGB').save(icon_path, 'PNG', optimize=True)
    print(f"   ✅ Saved: {icon_path}")
    
    # 2. Generate icon_foreground.png (432x432) - Android adaptive foreground
    print(f"\n📦 Generating icon_foreground.png (432x432)...")
    foreground = create_foreground_with_transparency(source_image, background_color)
    foreground_resized = foreground.resize((432, 432), Image.Resampling.LANCZOS)
    foreground_path = output_dir / 'icon_foreground.png'
    foreground_resized.save(foreground_path, 'PNG', optimize=True)
    print(f"   ✅ Saved: {foreground_path}")
    
    # 3. Generate icon_background.png (432x432) - Android adaptive background
    print(f"\n📦 Generating icon_background.png (432x432)...")
    background_image = Image.new('RGB', (432, 432), background_color)
    background_path = output_dir / 'icon_background.png'
    background_image.save(background_path, 'PNG', optimize=True)
    print(f"   ✅ Saved: {background_path}")
    
    # Summary
    print(f"\n✅ All app icons generated successfully!")
    print(f"\n📋 Generated files:")
    print(f"   - {icon_path.relative_to(PROJECT_ROOT)}")
    print(f"   - {foreground_path.relative_to(PROJECT_ROOT)}")
    print(f"   - {background_path.relative_to(PROJECT_ROOT)}")
    
    return True

def update_pubspec_yaml(pubspec_path):
    """
    Update pubspec.yaml to enable flutter_launcher_icons configuration.
    """
    print(f"\n📝 Updating pubspec.yaml...")
    
    if not pubspec_path.exists():
        print(f"❌ Error: pubspec.yaml not found: {pubspec_path}")
        return False
    
    # Read pubspec.yaml
    with open(pubspec_path, 'r') as f:
        content = f.read()
    
    original_content = content
    
    # Check if already configured (not commented)
    if re.search(r'^flutter_launcher_icons:\s*$', content, re.MULTILINE):
        print(f"   ✅ flutter_launcher_icons configuration already active")
        # Still check dev_dependencies
        if 'flutter_launcher_icons:' not in content.split('dev_dependencies:')[1].split('\nflutter:')[0]:
            # Need to add to dev_dependencies
            content = re.sub(
                r'(flutter_lints:.*?\n)',
                r'\1  flutter_launcher_icons: ^0.14.1\n',
                content,
                flags=re.MULTILINE
            )
            if content != original_content:
                with open(pubspec_path, 'w') as f:
                    f.write(content)
                print(f"   ✅ Added flutter_launcher_icons to dev_dependencies")
        return True
    
    # Step 1: Uncomment flutter_launcher_icons in dev_dependencies
    # Remove any commented version first
    content = re.sub(
        r'#\s*flutter_launcher_icons:\s*\^?[\d.]+.*?#.*?Commented out.*?\n',
        '',
        content,
        flags=re.DOTALL
    )
    
    # Also try simpler pattern - remove commented line
    content = re.sub(
        r'#\s*flutter_launcher_icons:\s*\^?[\d.]+.*?\n',
        '',
        content
    )
    
    # Now add it properly after flutter_lints
    if 'flutter_launcher_icons:' not in content.split('dev_dependencies:')[1].split('\nflutter:')[0]:
        content = re.sub(
            r'(flutter_lints:\s*\^?[\d.]+)\n',
            r'\1\n  flutter_launcher_icons: ^0.14.1\n',
            content
        )
    
    # Step 2: Replace commented flutter_launcher_icons config section
    flutter_icons_config = """flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/images/icon.png"
  adaptive_icon_background: "assets/images/icon_background.png"
  adaptive_icon_foreground: "assets/images/icon_foreground.png"
  remove_alpha_ios: true"""
    
    # Find and replace the commented block (multiline)
    pattern = r'#\s*flutter_launcher_icons:.*?#\s*remove_alpha_ios:\s*true'
    if re.search(pattern, content, re.DOTALL | re.MULTILINE):
        content = re.sub(pattern, flutter_icons_config, content, flags=re.DOTALL | re.MULTILINE)
        print(f"   ✅ Replaced commented flutter_launcher_icons configuration")
    else:
        # Add after assets section
        assets_match = re.search(r'(assets/predefined_hands\.yaml)', content)
        if assets_match:
            insert_pos = content.find('\n', assets_match.end())
            if insert_pos != -1:
                content = content[:insert_pos + 1] + '\n' + flutter_icons_config + '\n' + content[insert_pos + 1:]
                print(f"   ✅ Added flutter_launcher_icons configuration after assets section")
            else:
                content = content + '\n\n' + flutter_icons_config + '\n'
                print(f"   ✅ Added flutter_launcher_icons configuration at end")
        else:
            # Fallback: add after flutter section
            flutter_match = re.search(r'(uses-material-design:\s*true)', content)
            if flutter_match:
                insert_pos = content.find('\n', flutter_match.end())
                if insert_pos != -1:
                    content = content[:insert_pos + 1] + '\n' + flutter_icons_config + '\n' + content[insert_pos + 1:]
                    print(f"   ✅ Added flutter_launcher_icons configuration in flutter section")
                else:
                    content = content + '\n\n' + flutter_icons_config + '\n'
            else:
                content = content + '\n\n' + flutter_icons_config + '\n'
                print(f"   ✅ Added flutter_launcher_icons configuration at end")
    
    # Ensure dev_dependencies has flutter_launcher_icons
    dev_deps_section = content.split('dev_dependencies:')
    if len(dev_deps_section) > 1:
        dev_deps_content = dev_deps_section[1].split('\nflutter:')[0]
        if 'flutter_launcher_icons:' not in dev_deps_content:
            # Add it after flutter_lints
            content = re.sub(
                r'(flutter_lints:.*?\n)',
                r'\1  flutter_launcher_icons: ^0.14.1\n',
                content,
                flags=re.MULTILINE
            )
            print(f"   ✅ Added flutter_launcher_icons to dev_dependencies")
    
    # Write updated content
    with open(pubspec_path, 'w') as f:
        f.write(content)
    
    print(f"   ✅ Updated pubspec.yaml with flutter_launcher_icons configuration")
    return True

def verify_generated_files(output_dir):
    """
    Verify that all required icon files were generated.
    """
    print(f"\n🔍 Verifying generated files...")
    
    required_files = [
        'icon.png',
        'icon_foreground.png',
        'icon_background.png',
    ]
    
    all_exist = True
    for filename in required_files:
        file_path = output_dir / filename
        if file_path.exists():
            size = file_path.stat().st_size
            print(f"   ✅ {filename} ({size:,} bytes)")
        else:
            print(f"   ❌ {filename} - NOT FOUND")
            all_exist = False
    
    return all_exist

def run_flutter_commands(flutter_dir, skip_flutter=False):
    """
    Run flutter pub get and flutter pub run flutter_launcher_icons.
    """
    if skip_flutter:
        print(f"\n⏭️  Skipping Flutter commands (--skip-flutter flag)")
        return True
    
    flutter_dir = Path(flutter_dir)
    if not flutter_dir.exists():
        print(f"❌ Error: Flutter directory not found: {flutter_dir}")
        return False
    
    print(f"\n📦 Running Flutter commands...")
    
    # Run flutter pub get
    print(f"   Running: flutter pub get")
    try:
        result = subprocess.run(
            ['flutter', 'pub', 'get'],
            cwd=flutter_dir,
            capture_output=True,
            text=True,
            check=True
        )
        print(f"   ✅ flutter pub get completed")
        if result.stdout:
            # Show any important output
            lines = result.stdout.strip().split('\n')
            for line in lines[-5:]:  # Show last 5 lines
                if line.strip():
                    print(f"      {line}")
    except subprocess.CalledProcessError as e:
        print(f"   ❌ Error running flutter pub get:")
        print(f"      {e.stderr if e.stderr else e.stdout}")
        return False
    except FileNotFoundError:
        print(f"   ❌ Error: flutter command not found. Make sure Flutter is installed and in PATH.")
        return False
    
    # Run flutter pub run flutter_launcher_icons
    print(f"   Running: flutter pub run flutter_launcher_icons")
    try:
        result = subprocess.run(
            ['flutter', 'pub', 'run', 'flutter_launcher_icons'],
            cwd=flutter_dir,
            capture_output=True,
            text=True,
            check=True
        )
        print(f"   ✅ flutter_launcher_icons completed")
        if result.stdout:
            # Show output
            lines = result.stdout.strip().split('\n')
            for line in lines:
                if line.strip() and ('✅' in line or '✓' in line or 'Error' in line or 'error' in line):
                    print(f"      {line}")
    except subprocess.CalledProcessError as e:
        print(f"   ❌ Error running flutter_launcher_icons:")
        print(f"      {e.stderr if e.stderr else e.stdout}")
        return False
    
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Generate Flutter app icons from a single source image and configure Flutter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use default paths and run full process
  python3 generate_app_icons.py
  
  # Specify custom source and output
  python3 generate_app_icons.py --source /path/to/image.png --output /path/to/output/
  
  # Skip Flutter commands (only generate images and update pubspec)
  python3 generate_app_icons.py --skip-flutter
        """
    )
    
    parser.add_argument(
        '--source',
        type=str,
        default=str(DEFAULT_SOURCE),
        help=f'Path to source image (default: {DEFAULT_SOURCE.relative_to(PROJECT_ROOT)})'
    )
    
    parser.add_argument(
        '--output',
        type=str,
        default=str(DEFAULT_OUTPUT),
        help=f'Output directory for generated icons (default: {DEFAULT_OUTPUT.relative_to(PROJECT_ROOT)})'
    )
    
    parser.add_argument(
        '--skip-flutter',
        action='store_true',
        help='Skip running Flutter commands (only generate images and update pubspec)'
    )
    
    args = parser.parse_args()
    
    # Check if Pillow is available
    try:
        from PIL import Image
    except ImportError:
        print("❌ Error: Pillow is not installed.")
        print("   Install it with: pip install Pillow")
        return 1
    
    # Step 1: Generate app icons
    print("=" * 60)
    print("🎨 Step 1: Generating app icons from source image")
    print("=" * 60)
    if not generate_app_icons(args.source, args.output):
        return 1
    
    # Verify generated files
    if not verify_generated_files(Path(args.output)):
        print(f"   ⚠️  Warning: Some files may be missing, but continuing...")
    
    # Step 2: Update pubspec.yaml
    print("\n" + "=" * 60)
    print("📝 Step 2: Updating pubspec.yaml")
    print("=" * 60)
    if not update_pubspec_yaml(PUBSPEC_PATH):
        return 1
    
    # Step 3: Run Flutter commands
    if not args.skip_flutter:
        print("\n" + "=" * 60)
        print("🚀 Step 3: Running Flutter commands")
        print("=" * 60)
        if not run_flutter_commands(FLUTTER_DIR, skip_flutter=args.skip_flutter):
            return 1
    
    # Final summary
    print("\n" + "=" * 60)
    print("✅ Complete! All steps finished successfully")
    print("=" * 60)
    print(f"\n📋 Summary:")
    print(f"   ✅ Generated app icon images")
    print(f"   ✅ Updated pubspec.yaml")
    if not args.skip_flutter:
        print(f"   ✅ Ran flutter pub get")
        print(f"   ✅ Ran flutter_launcher_icons")
    else:
        print(f"   ⏭️  Skipped Flutter commands (use without --skip-flutter to run them)")
    print(f"\n🎉 Your app icons are now configured and ready!")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
