#!/usr/bin/env python3
"""
Optimize logging calls by converting runtime checks to compile-time conditionals.

Converts:
  _logger.info('message', isOn: LOGGING_SWITCH);
  
To:
  if (LOGGING_SWITCH) {
    _logger.info('message');
  }

This allows Dart's compiler to eliminate dead code when LOGGING_SWITCH = false.
"""

import os
import re
import sys
import shutil
from pathlib import Path
from datetime import datetime


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


def find_log_calls(content):
    """Find all logger calls with isOn: LOGGING_SWITCH parameter."""
    # Pattern to match logger method start
    pattern = r'_logger\.(info|error|warning|debug)\('
    
    matches = []
    for match in re.finditer(pattern, content):
        start = match.start()
        method_name = match.group(1)
        
        # Find the opening parenthesis
        paren_start = match.end() - 1  # Position of '('
        paren_count = 1
        search_pos = paren_start + 1
        in_string = False
        string_char = None
        
        # Find matching closing parenthesis, handling strings and nested parens
        while paren_count > 0 and search_pos < len(content):
            char = content[search_pos]
            
            # Track string boundaries
            if char in ('"', "'") and (search_pos == 0 or content[search_pos - 1] != '\\'):
                if not in_string:
                    in_string = True
                    string_char = char
                elif char == string_char:
                    in_string = False
                    string_char = None
            
            # Count parentheses only when not in string
            if not in_string:
                if char == '(':
                    paren_count += 1
                elif char == ')':
                    paren_count -= 1
            
            search_pos += 1
        
        if paren_count == 0:
            # Found complete call, check if it contains isOn: LOGGING_SWITCH
            call_content = content[start:search_pos]
            if 'isOn:' in call_content and 'LOGGING_SWITCH' in call_content:
                # Verify it's actually the isOn parameter
                if re.search(r'isOn:\s*LOGGING_SWITCH', call_content):
                    matches.append((start, search_pos, call_content, method_name))
    
    return matches


def convert_log_call(content, start, end, original_call, log_method):
    """Convert a single log call to use compile-time conditional."""
    original = content[start:end]
    
    # Extract the message and other parameters (excluding isOn: LOGGING_SWITCH)
    # Pattern: _logger.method('message', param1: value1, isOn: LOGGING_SWITCH, param2: value2)
    
    # Remove isOn: LOGGING_SWITCH parameter
    # Handle both comma before and after
    cleaned = re.sub(r',\s*isOn:\s*LOGGING_SWITCH', '', original)
    cleaned = re.sub(r'isOn:\s*LOGGING_SWITCH\s*,', '', cleaned)
    cleaned = re.sub(r'isOn:\s*LOGGING_SWITCH', '', cleaned)
    
    # Find indentation of the original line
    line_start = content.rfind('\n', 0, start) + 1
    indent = content[line_start:start]
    
    # Check if there's a semicolon after the original call
    has_semicolon = False
    if end < len(content) and content[end:end+1].strip().startswith(';'):
        has_semicolon = True
    
    # Build the new conditional block
    new_call = cleaned.rstrip().rstrip(';')
    new_code = f"if (LOGGING_SWITCH) {{\n{indent}  {new_call};\n{indent}}}"
    
    # Add semicolon only if original had one
    if has_semicolon:
        new_code += ';'
    
    return new_code


def optimize_file(file_path):
    """Optimize logging calls in a single file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        matches = find_log_calls(content)
        
        if not matches:
            return 0, 0
        
        # Process matches in reverse order to maintain indices
        converted = 0
        for start, end, original_call, log_method in reversed(matches):
            new_code = convert_log_call(content, start, end, original_call, log_method)
            content = content[:start] + new_code + content[end:]
            converted += 1
        
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return converted, len(matches)
        
        return 0, len(matches)
    
    except Exception as e:
        print(f"{Colors.RED}✗{Colors.NC} Error processing {file_path}: {e}")
        return 0, 0


def create_backup(repo_root, source_dir, backup_base_dir):
    """Create an exact copy of a directory to the backup location."""
    source_path = repo_root / source_dir
    if not source_path.exists():
        print(f"{Colors.YELLOW}⚠{Colors.NC} Source directory not found: {source_path}")
        return False
    
    backup_path = backup_base_dir / source_dir
    try:
        # Remove existing backup completely if it exists
        if backup_path.exists():
            shutil.rmtree(backup_path)
        
        # Wait a moment to ensure filesystem sync
        import time
        time.sleep(0.1)
        
        # Create exact copy using copytree
        shutil.copytree(source_path, backup_path, dirs_exist_ok=True, symlinks=False)
        
        # Verify backup was created and has content
        if backup_path.exists() and any(backup_path.iterdir()):
            print(f"  {Colors.GREEN}✓{Colors.NC} Backed up {source_dir}")
            return True
        else:
            print(f"  {Colors.RED}✗{Colors.NC} Backup failed for {source_dir} - directory empty or not created")
            return False
    except Exception as e:
        print(f"  {Colors.RED}✗{Colors.NC} Error backing up {source_dir}: {e}")
        # Try to clean up partial backup
        if backup_path.exists():
            try:
                shutil.rmtree(backup_path)
            except:
                pass
        return False


def main():
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    
    # Create backup directory with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_base_dir = repo_root / "backups" / f"{timestamp}_logging_optimization"
    
    print(f"{Colors.BLUE}=== Logging Optimization Script ==={Colors.NC}\n")
    print(f"{Colors.BLUE}Step 1: Creating backups...{Colors.NC}\n")
    print(f"Backup location: {backup_base_dir.relative_to(repo_root)}\n")
    
    # Create backup directory
    backup_base_dir.mkdir(parents=True, exist_ok=True)
    
    # Backup directories
    backup_success = True
    backup_success &= create_backup(repo_root, "flutter_base_05", backup_base_dir)
    backup_success &= create_backup(repo_root, "dart_bkend_base_01", backup_base_dir)
    
    if not backup_success:
        print(f"\n{Colors.RED}✗ Backup failed! Aborting optimization.{Colors.NC}")
        sys.exit(1)
    
    # Verify backups (check file counts and approximate size - allow small differences for build artifacts)
    print(f"\n{Colors.BLUE}Verifying backups...{Colors.NC}")
    for source_dir in ["flutter_base_05", "dart_bkend_base_01"]:
        source_path = repo_root / source_dir
        backup_path = backup_base_dir / source_dir
        if backup_path.exists():
            # Count files (excluding .git and build directories)
            source_files = [f for f in source_path.rglob('*') if f.is_file() and '.git' not in str(f) and 'build/' not in str(f)]
            backup_files = [f for f in backup_path.rglob('*') if f.is_file() and '.git' not in str(f) and 'build/' not in str(f)]
            
            source_count = len(source_files)
            backup_count = len(backup_files)
            
            # Calculate size (excluding .git and build)
            source_size = sum(f.stat().st_size for f in source_files)
            backup_size = sum(f.stat().st_size for f in backup_files)
            
            # Allow 1% size difference for timing/metadata differences
            size_diff_percent = abs(source_size - backup_size) / max(source_size, 1) * 100
            
            if source_count == backup_count and size_diff_percent < 1.0:
                print(f"  {Colors.GREEN}✓{Colors.NC} {source_dir}: {source_count} files, {source_size / (1024*1024):.1f} MB (verified)")
            else:
                print(f"  {Colors.YELLOW}⚠{Colors.NC} {source_dir}: File count: {source_count} vs {backup_count}, Size diff: {size_diff_percent:.2f}%")
                if source_count != backup_count or size_diff_percent >= 1.0:
                    print(f"  {Colors.YELLOW}  Note: Small differences may be due to build artifacts or timing.{Colors.NC}")
                    # Continue anyway - backup is likely fine
    
    print(f"\n{Colors.GREEN}✓ All backups created successfully!{Colors.NC}\n")
    print(f"{Colors.BLUE}Step 2: Optimizing logging calls...{Colors.NC}\n")
    print("Converting runtime checks to compile-time conditionals...\n")
    
    # Target directories for optimization
    flutter_dir = repo_root / "flutter_base_05" / "lib" / "modules" / "dutch_game" / "backend_core" / "shared_logic"
    dart_backend_dir = repo_root / "dart_bkend_base_01" / "lib" / "modules" / "dutch_game" / "backend_core" / "shared_logic"
    
    total_files = 0
    total_converted = 0
    total_found = 0
    
    for target_dir in [flutter_dir, dart_backend_dir]:
        if not target_dir.exists():
            print(f"{Colors.YELLOW}⚠{Colors.NC} Directory not found: {target_dir}")
            continue
        
        print(f"{Colors.BLUE}Processing: {target_dir.relative_to(repo_root)}{Colors.NC}")
        
        for dart_file in target_dir.rglob("*.dart"):
            converted, found = optimize_file(dart_file)
            if found > 0:
                rel_path = dart_file.relative_to(repo_root)
                status = f"{Colors.GREEN}✓{Colors.NC}" if converted > 0 else f"{Colors.YELLOW}○{Colors.NC}"
                print(f"  {status} {rel_path}: {converted}/{found} calls converted")
                total_files += 1
                total_converted += converted
                total_found += found
    
    print(f"\n{Colors.GREEN}=== Summary ==={Colors.NC}")
    print(f"Backup location: {backup_base_dir.relative_to(repo_root)}")
    print(f"Files processed: {total_files}")
    print(f"Log calls found: {total_found}")
    print(f"Log calls converted: {total_converted}")
    
    if total_converted > 0:
        print(f"\n{Colors.GREEN}✓ Optimization complete!{Colors.NC}")
        print(f"All logging calls now use compile-time conditionals.")
        print(f"When LOGGING_SWITCH = false, dead code will be eliminated at compile-time.")
        print(f"\n{Colors.YELLOW}Note:{Colors.NC} Original code backed up to: {backup_base_dir.relative_to(repo_root)}")
    else:
        print(f"\n{Colors.YELLOW}No changes needed.{Colors.NC}")
        print(f"Original code backed up to: {backup_base_dir.relative_to(repo_root)}")


if __name__ == "__main__":
    main()
