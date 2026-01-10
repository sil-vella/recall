#!/usr/bin/env python3
"""
Generate Flutter Splash Screen from Source Image

This script takes a splash screen image and configures flutter_native_splash:
- Validates image dimensions (should be rectangular, portrait for mobile)
- Copies the source image to assets/images/splash_screen.png
- Updates pubspec.yaml to enable flutter_native_splash configuration
- Runs flutter pub get
- Runs dart run flutter_native_splash:create

Recommended image dimensions:
- 1080×1920 (Full HD portrait - minimum)
- 1440×2560 (QHD portrait - recommended)
- 2048×2732 (iPad Pro portrait - optional)

Usage:
    python3 generate_splash_screen.py [--source SOURCE_PATH] [--output OUTPUT_DIR] [--skip-flutter] [--auto-resize]

Requirements:
    pip install Pillow
"""

import argparse
import sys
import subprocess
import re
from pathlib import Path
from PIL import Image
import shutil

# Default paths
PROJECT_ROOT = Path(__file__).parent.parent.parent
DEFAULT_SOURCE = PROJECT_ROOT / 'branding' / 'images' / 'app_splash.png'
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

def rgb_to_hex(rgb):
    """Convert RGB tuple to hex color string."""
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"

def validate_and_prepare_splash_image(source_path, output_dir, auto_resize=False):
    """
    Validate splash screen image dimensions and prepare for Flutter.
    
    Returns: (success, hex_color, warnings)
    """
    source_path = Path(source_path)
    output_dir = Path(output_dir)
    warnings = []
    
    # Validate source image exists
    if not source_path.exists():
        print(f"❌ Error: Source image not found: {source_path}")
        return False, None, []
    
    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"📸 Loading source image: {source_path}")
    try:
        source_image = Image.open(source_path)
    except Exception as e:
        print(f"❌ Error: Failed to load image: {e}")
        return False, None, []
    
    width, height = source_image.size
    aspect_ratio = width / height
    print(f"✅ Source image loaded: {width}×{height} ({source_image.mode})")
    print(f"   Aspect ratio: {aspect_ratio:.2f}:1")
    
    # Validate dimensions
    print(f"\n🔍 Validating splash screen dimensions...")
    
    # Check if square (not ideal for splash screens)
    if abs(width - height) < 10:  # Allow 10px tolerance
        warnings.append("Image is square. Splash screens should be rectangular (portrait for mobile).")
        print(f"   ⚠️  Warning: Image is square ({width}×{height})")
        print(f"      Recommended: Portrait orientation (e.g., 1080×1920 or 1440×2560)")
    else:
        print(f"   ✅ Image is rectangular")
    
    # Check aspect ratio
    # Ideal portrait ratio is ~0.5625 (9:16), common ratios: 0.5-0.6
    # Landscape would be > 1.0
    if aspect_ratio > 1.0:
        warnings.append("Image is landscape orientation. Portrait is recommended for mobile apps.")
        print(f"   ⚠️  Warning: Landscape orientation detected")
        print(f"      Recommended: Portrait (height > width) for mobile apps")
    elif aspect_ratio < 0.4 or aspect_ratio > 0.7:
        warnings.append(f"Unusual aspect ratio ({aspect_ratio:.2f}:1). Standard portrait is ~0.56:1 (9:16).")
        print(f"   ⚠️  Warning: Unusual aspect ratio")
        print(f"      Recommended: ~0.56:1 (9:16 portrait, e.g., 1080×1920)")
    else:
        print(f"   ✅ Portrait orientation with good aspect ratio")
    
    # Check minimum dimensions
    min_dimension = min(width, height)
    if min_dimension < 1080:
        warnings.append(f"Image is small ({width}×{height}). Recommended minimum: 1080×1920 for good quality.")
        print(f"   ⚠️  Warning: Image may be too small for high-DPI displays")
        print(f"      Recommended minimum: 1080×1920 (Full HD portrait)")
    else:
        print(f"   ✅ Dimensions are adequate for high-DPI displays")
    
    # Recommended dimensions
    recommended_sizes = [
        "1080×1920 (Full HD portrait - recommended minimum)",
        "1440×2560 (QHD portrait - recommended)",
        "2048×2732 (iPad Pro portrait - optional)",
    ]
    print(f"\n   💡 Recommended sizes:")
    for size in recommended_sizes:
        print(f"      - {size}")
    
    # Auto-resize if requested
    if auto_resize and warnings:
        print(f"\n🔄 Auto-resizing to recommended dimensions...")
        # Resize to 1440×2560 (good balance)
        target_width, target_height = 1440, 2560
        resized_image = source_image.resize((target_width, target_height), Image.Resampling.LANCZOS)
        source_image = resized_image
        print(f"   ✅ Resized to {target_width}×{target_height}")
        warnings.append(f"Image was auto-resized from {width}×{height} to {target_width}×{target_height}")
    
    # Extract background color for configuration
    print(f"\n🎨 Extracting background color...")
    background_color = extract_background_color(source_image)
    hex_color = rgb_to_hex(background_color)
    print(f"   Background color: RGB{background_color} ({hex_color})")
    
    # Copy image to assets directory
    output_path = output_dir / 'splash_screen.png'
    print(f"\n📦 Saving splash image to assets...")
    try:
        # Ensure it's saved as PNG
        if source_image.mode == 'RGBA':
            source_image.save(output_path, 'PNG', optimize=True)
        else:
            # Convert to RGB if needed
            rgb_image = source_image.convert('RGB')
            rgb_image.save(output_path, 'PNG', optimize=True)
        file_size = output_path.stat().st_size
        print(f"   ✅ Saved: {output_path} ({file_size:,} bytes)")
    except Exception as e:
        print(f"   ❌ Error saving image: {e}")
        return False, None, []
    
    return True, hex_color, warnings

def update_pubspec_yaml(pubspec_path, background_color):
    """
    Update pubspec.yaml to enable flutter_native_splash configuration.
    """
    print(f"\n📝 Updating pubspec.yaml...")
    
    if not pubspec_path.exists():
        print(f"❌ Error: pubspec.yaml not found: {pubspec_path}")
        return False
    
    # Read pubspec.yaml
    with open(pubspec_path, 'r') as f:
        content = f.read()
    
    original_content = content
    
    # Step 1: Fix any incorrectly placed flutter_native_splash in dependencies section
    # Look for flutter_native_splash: followed by configuration (not a version number)
    deps_section_pattern = r'(dependencies:.*?)(\n  flutter_native_splash:\s*\n(?:  (?:color|image|android|ios|web|android_gravity|ios_content_mode|fullscreen|android_12):.*?\n)+)'
    deps_match = re.search(deps_section_pattern, content, re.DOTALL)
    if deps_match:
        print(f"   🔧 Found incorrectly placed flutter_native_splash config in dependencies section")
        print(f"      Removing configuration from dependencies...")
        # Remove the config block from dependencies
        content = re.sub(deps_section_pattern, r'\1', content, flags=re.DOTALL)
        # Ensure flutter_native_splash package is in dependencies with version
        if 'flutter_native_splash:' not in content.split('dependencies:')[1].split('\ndev_dependencies:')[0]:
            # Add it after package_info_plus or last dependency
            if 'package_info_plus:' in content:
                content = re.sub(
                    r'(package_info_plus:.*?\n)',
                    r'\1  flutter_native_splash: ^2.4.0\n',
                    content
                )
            else:
                # Find the last dependency before dev_dependencies
                deps_end = content.find('\ndev_dependencies:')
                if deps_end != -1:
                    # Find last line in dependencies
                    deps_section = content[:deps_end]
                    last_dep_match = re.search(r'(\n  \w+.*?\n)', deps_section[::-1])
                    if last_dep_match:
                        insert_pos = deps_end - last_dep_match.end()
                        content = content[:insert_pos] + '\n  flutter_native_splash: ^2.4.0' + content[insert_pos:]
        print(f"      ✅ Fixed dependencies section")
    
    # Step 2: Ensure flutter_native_splash package is in dependencies with version
    deps_section = content.split('dependencies:')
    if len(deps_section) > 1:
        deps_content = deps_section[1].split('\ndev_dependencies:')[0]
        # Check if flutter_native_splash exists but without version (just the name)
        if re.search(r'^\s+flutter_native_splash:\s*$', deps_content, re.MULTILINE):
            print(f"   🔧 Found flutter_native_splash without version in dependencies")
            content = re.sub(
                r'(\n\s+flutter_native_splash:\s*)\n',
                r'\1^2.4.0\n',
                content
            )
            print(f"      ✅ Added version to flutter_native_splash dependency")
        elif not re.search(r'^\s+flutter_native_splash:\s*\^?[\d.]+', deps_content, re.MULTILINE):
            print(f"   📦 Adding flutter_native_splash to dependencies...")
            # Add after package_info_plus if it exists
            if 'package_info_plus:' in content:
        content = re.sub(
                    r'(package_info_plus:.*?\n)',
            r'\1  flutter_native_splash: ^2.4.0\n',
            content
        )
            else:
                # Add at end of dependencies section
                deps_end = content.find('\ndev_dependencies:')
                if deps_end != -1:
                    content = content[:deps_end] + '\n  flutter_native_splash: ^2.4.0' + content[deps_end:]
            print(f"      ✅ Added flutter_native_splash: ^2.4.0 to dependencies")
    
    # Step 3: Update or add flutter_native_splash configuration at root level
    splash_config = f"""flutter_native_splash:
  color: "{background_color}"
  image: assets/images/splash_screen.png
  android: true
  ios: true
  web: false
  android_gravity: fill
  ios_content_mode: scaleToFill
  fullscreen: true
  android_12:
    color: "{background_color}"
    image: assets/images/splash_screen.png
    icon_background_color: "{background_color}"
"""
    
    # Check if configuration already exists at root level (not in dependencies)
    # Look for flutter_native_splash: at the start of a line (root level)
    # Match until next top-level key (starts at beginning of line, not indented) or end of file
    root_config_pattern = r'^flutter_native_splash:.*?(?=\n[a-z_]+:|\n# [A-Z]|\Z)'
    root_match = re.search(root_config_pattern, content, re.MULTILINE | re.DOTALL)
    
    if root_match:
        print(f"   ✅ Found existing flutter_native_splash configuration at root level")
        # Replace the entire flutter_native_splash section to ensure consistency
        # Match from flutter_native_splash: to the next top-level key or end of file
        content = re.sub(
            r'^flutter_native_splash:.*?(?=\n[a-z_]+:|\n# [A-Z]|\Z)',
            splash_config.rstrip(),
            content,
            flags=re.MULTILINE | re.DOTALL
        )
        print(f"      ✅ Updated existing configuration with new color: {background_color}")
    else:
        # Add configuration after flutter_launcher_icons section
        launcher_icons_match = re.search(r'(flutter_launcher_icons:.*?remove_alpha_ios:\s*true)', content, re.DOTALL)
        if launcher_icons_match:
            insert_pos = content.find('\n', launcher_icons_match.end())
            if insert_pos != -1:
                content = content[:insert_pos + 1] + '\n' + splash_config + content[insert_pos + 1:]
                print(f"   ✅ Added flutter_native_splash configuration after flutter_launcher_icons")
            else:
                content = content + '\n\n' + splash_config
                print(f"   ✅ Added flutter_native_splash configuration at end")
        else:
            # Fallback: add after flutter section
            flutter_match = re.search(r'(uses-material-design:\s*true)', content)
            if flutter_match:
                # Find end of flutter section (before next top-level key)
                flutter_end = content.find('\n\n', flutter_match.end())
                if flutter_end == -1:
                    flutter_end = content.find('\n\w', flutter_match.end())
                if flutter_end != -1:
                    content = content[:flutter_end] + '\n\n' + splash_config + content[flutter_end:]
                    print(f"   ✅ Added flutter_native_splash configuration after flutter section")
                else:
                    content = content + '\n\n' + splash_config
                    print(f"   ✅ Added flutter_native_splash configuration at end")
            else:
                content = content + '\n\n' + splash_config
                print(f"   ✅ Added flutter_native_splash configuration at end")
    
    # Write updated content
    if content != original_content:
    with open(pubspec_path, 'w') as f:
        f.write(content)
        print(f"   ✅ Updated pubspec.yaml with flutter_native_splash configuration")
    else:
        print(f"   ℹ️  No changes needed to pubspec.yaml")
    
    return True

def verify_generated_files(output_dir):
    """
    Verify that the splash screen image was generated.
    """
    print(f"\n🔍 Verifying generated files...")
    
    splash_path = output_dir / 'splash_screen.png'
    
    if splash_path.exists():
        size = splash_path.stat().st_size
        print(f"   ✅ splash_screen.png ({size:,} bytes)")
        return True
    else:
        print(f"   ❌ splash_screen.png - NOT FOUND")
        return False

def run_flutter_commands(flutter_dir, skip_flutter=False):
    """
    Run flutter pub get and dart run flutter_native_splash:create.
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
    
    # Run dart run flutter_native_splash:create
    print(f"   Running: dart run flutter_native_splash:create")
    try:
        result = subprocess.run(
            ['dart', 'run', 'flutter_native_splash:create'],
            cwd=flutter_dir,
            capture_output=True,
            text=True,
            check=True
        )
        print(f"   ✅ flutter_native_splash:create completed")
        if result.stdout:
            # Show output
            lines = result.stdout.strip().split('\n')
            for line in lines:
                if line.strip() and ('✅' in line or '✓' in line or 'Error' in line or 'error' in line or 'Success' in line or 'success' in line):
                    print(f"      {line}")
    except subprocess.CalledProcessError as e:
        print(f"   ❌ Error running flutter_native_splash:create:")
        print(f"      {e.stderr if e.stderr else e.stdout}")
        return False
    
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Generate Flutter splash screen from source image and configure Flutter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use default paths and run full process
  python3 generate_splash_screen.py
  
  # Specify custom source and output
  python3 generate_splash_screen.py --source /path/to/splash.png --output /path/to/output/
  
  # Skip Flutter commands (only generate images and update pubspec)
  python3 generate_splash_screen.py --skip-flutter
  
  # Auto-resize image to recommended dimensions if validation fails
  python3 generate_splash_screen.py --auto-resize
        """
    )
    
    parser.add_argument(
        '--source',
        type=str,
        default=str(DEFAULT_SOURCE),
        help=f'Path to source splash image (default: {DEFAULT_SOURCE.relative_to(PROJECT_ROOT)})'
    )
    
    parser.add_argument(
        '--output',
        type=str,
        default=str(DEFAULT_OUTPUT),
        help=f'Output directory for splash image (default: {DEFAULT_OUTPUT.relative_to(PROJECT_ROOT)})'
    )
    
    parser.add_argument(
        '--skip-flutter',
        action='store_true',
        help='Skip running Flutter commands (only generate images and update pubspec)'
    )
    
    parser.add_argument(
        '--auto-resize',
        action='store_true',
        help='Automatically resize image to recommended dimensions (1440×2560) if validation fails'
    )
    
    args = parser.parse_args()
    
    # Check if Pillow is available
    try:
        from PIL import Image
    except ImportError:
        print("❌ Error: Pillow is not installed.")
        print("   Install it with: pip install Pillow")
        return 1
    
    # Step 1: Prepare splash image
    print("=" * 60)
    print("🎨 Step 1: Preparing splash screen image")
    print("=" * 60)
    success, background_color, warnings = validate_and_prepare_splash_image(
        args.source, args.output, auto_resize=args.auto_resize
    )
    if not success:
        return 1
    
    # Show warnings if any
    if warnings:
        print(f"\n⚠️  Warnings:")
        for warning in warnings:
            print(f"   - {warning}")
        if not args.auto_resize:
            print(f"\n   💡 Tip: Use --auto-resize to automatically fix dimension issues")
    
    # Verify generated files
    if not verify_generated_files(Path(args.output)):
        print(f"   ⚠️  Warning: Splash image may be missing, but continuing...")
    
    # Step 2: Update pubspec.yaml
    print("\n" + "=" * 60)
    print("📝 Step 2: Updating pubspec.yaml")
    print("=" * 60)
    if not update_pubspec_yaml(PUBSPEC_PATH, background_color):
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
    print(f"   ✅ Validated and prepared splash screen image")
    if warnings:
        print(f"   ⚠️  {len(warnings)} warning(s) - see above for details")
    print(f"   ✅ Updated pubspec.yaml")
    if not args.skip_flutter:
        print(f"   ✅ Ran flutter pub get")
        print(f"   ✅ Ran flutter_native_splash:create")
    else:
        print(f"   ⏭️  Skipped Flutter commands (use without --skip-flutter to run them)")
    print(f"\n🎉 Your splash screen is now configured and ready!")
    print(f"\n💡 Recommended splash screen dimensions:")
    print(f"   - 1080×1920 (Full HD portrait - minimum)")
    print(f"   - 1440×2560 (QHD portrait - recommended)")
    print(f"   - 2048×2732 (iPad Pro portrait - optional)")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
