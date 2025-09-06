#!/usr/bin/env python3
"""
Script to remove all custom_log() calls from Python Base 04 project
except from the tools/logger/ directory.
"""

import os
import re
import glob
from pathlib import Path

def remove_custom_logs_from_file(file_path):
    """Remove all custom_log() calls from a single file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        # Remove import statement
        content = re.sub(r'from tools\.logger\.custom_logging import custom_log\s*\n?', '', content)
        
        # Remove all custom_log() calls - handle both single line and multi-line
        # Pattern to match custom_log calls with their arguments (including multi-line)
        content = re.sub(r'custom_log\([^)]*\)\s*\n?', '', content, flags=re.MULTILINE)
        
        # Also remove lines that are just custom_log calls
        lines = content.split('\n')
        filtered_lines = []
        
        for line in lines:
            # Skip lines that are just custom_log calls or whitespace
            if not re.match(r'^\s*custom_log\(.*\)\s*$', line):
                # If line contains custom_log but also other content, remove just the custom_log part
                if 'custom_log(' in line:
                    # Remove custom_log calls but keep the rest of the line
                    cleaned_line = re.sub(r'custom_log\([^)]*\)\s*', '', line)
                    if cleaned_line.strip():
                        filtered_lines.append(cleaned_line)
                else:
                    filtered_lines.append(line)
        
        # Join lines back
        content = '\n'.join(filtered_lines)
        
        # Only write if content changed
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return True
        
        return False
        
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
        return False

def main():
    """Main function to process all Python files."""
    base_dir = Path("python_base_04")
    
    if not base_dir.exists():
        print("Error: python_base_04 directory not found")
        return
    
    # Find all Python files except in tools/logger/
    python_files = []
    
    # Get all .py files
    for py_file in base_dir.rglob("*.py"):
        # Skip files in tools/logger/ directory
        if "tools/logger/" in str(py_file):
            print(f"Skipping logger file: {py_file}")
            continue
        
        python_files.append(py_file)
    
    print(f"Found {len(python_files)} Python files to process")
    
    processed_count = 0
    modified_count = 0
    
    for file_path in python_files:
        print(f"Processing: {file_path}")
        if remove_custom_logs_from_file(file_path):
            modified_count += 1
            print(f"  ✓ Modified")
        else:
            print(f"  - No changes needed")
        processed_count += 1
    
    print(f"\nCompleted!")
    print(f"Processed: {processed_count} files")
    print(f"Modified: {modified_count} files")

if __name__ == "__main__":
    main()
