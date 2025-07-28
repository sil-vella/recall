#!/usr/bin/env python3
"""
Update Declarations Reference

Simple script to regenerate the HTML reference from YAML declarations.
Run this script whenever you add, modify, or remove YAML declarations.
"""

import os
import sys
from pathlib import Path

# Add the current directory to Python path
current_dir = Path(__file__).parent
sys.path.insert(0, str(current_dir))

from generate_declarations_reference import DeclarationsReferenceGenerator


def main():
    """Update the declarations reference"""
    print("🔄 Updating Recall Game Declarations Reference...")
    
    generator = DeclarationsReferenceGenerator()
    output_path = generator.generate_and_save()
    
    print(f"\n✅ Reference updated successfully!")
    print(f"📁 Output file: {output_path}")
    print(f"🌐 Open the HTML file in your browser to view the reference")
    
    # Try to open the file in default browser (macOS)
    try:
        import subprocess
        subprocess.run(['open', output_path])
        print("🚀 Opened reference in default browser")
    except:
        print("💡 Manually open the HTML file in your browser")


if __name__ == "__main__":
    main() 