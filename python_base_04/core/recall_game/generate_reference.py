#!/usr/bin/env python3
"""
Recall Game Declarations Reference Generator

Simple launcher script to generate the HTML reference from the main recall_game directory.
"""

import sys
from pathlib import Path

# Add the reference_system directory to Python path
current_dir = Path(__file__).parent
reference_system_dir = current_dir / "reference_system"
sys.path.insert(0, str(reference_system_dir))

from generate_declarations_reference import DeclarationsReferenceGenerator


def main():
    """Generate the declarations reference"""
    print("🎮 Recall Game Declarations Reference Generator")
    print("=" * 50)
    
    generator = DeclarationsReferenceGenerator()
    output_path = generator.generate_and_save()
    
    print(f"\n✅ Reference generated successfully!")
    print(f"📁 Output file: {output_path}")
    print(f"🌐 Open the HTML file in your browser to view the reference")
    
    # Try to open the file in default browser (macOS)
    try:
        import subprocess
        subprocess.run(['open', output_path])
        print("🚀 Opened reference in default browser")
    except:
        print("💡 Manually open the HTML file in your browser")
    
    print("\n📝 To update the reference after adding new declarations:")
    print("   python generate_reference.py")


if __name__ == "__main__":
    main() 