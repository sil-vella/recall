#!/usr/bin/env python3
"""
Build and Push Docker Image Script
This script builds the Flask app Docker image and pushes it to Docker Hub.
It temporarily comments out custom_log() calls during the build process.
"""

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple, Optional

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

# Get script directory and project root
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent

# Configuration
DOCKER_USERNAME = os.environ.get('DOCKER_USERNAME', 'silvella')
IMAGE_NAME = 'cleco_flask_app'
IMAGE_TAG = os.environ.get('IMAGE_TAG', 'latest')
DOCKERFILE_PATH = PROJECT_ROOT / 'python_base_04' / 'Dockerfile'
BUILD_CONTEXT = PROJECT_ROOT / 'python_base_04'

# Track modified files for restoration
modified_files = []

# Track secret file backups for restoration
secret_backups = {}

def get_indentation(line: str) -> str:
    """Get the leading whitespace (indentation) from a line."""
    match = re.match(r'^(\s*)', line)
    return match.group(1) if match else ''

def is_control_flow_line(line: str) -> bool:
    """Check if a line is a control flow statement (if, else, for, while, try, except, finally)."""
    stripped = line.strip()
    # Match control flow keywords followed by optional whitespace, optional content, and then a colon
    # This handles both "else:" and "elif condition:" cases
    return bool(re.match(r'^(if|else|elif|for|while|try|except|finally)(\s.*)?:', stripped))

def is_only_statement_in_block(lines: List[str], index: int) -> bool:
    """Check if the custom_log line at index is the only statement in its block, or if all statements in the block are custom_log calls.
    Returns True if this is the FIRST custom_log call in a block that contains ONLY custom_log calls."""
    if index == 0:
        return False
    
    current_line = lines[index]
    current_indent = get_indentation(current_line)
    
    # Find the control flow statement by looking backwards through comments and empty lines
    # The control flow statement should be at LESS indentation than the custom_log line
    control_flow_index = None
    for i in range(index - 1, -1, -1):
        check_line = lines[i]
        check_indent = get_indentation(check_line)
        check_stripped = check_line.strip()
        
        # Skip empty lines and comments
        if not check_stripped or check_stripped.startswith('#'):
            continue
        
        # If we've gone back to a line with less indentation, check if it's a control flow statement
        if len(check_indent) < len(current_indent):
            if is_control_flow_line(check_stripped):
                control_flow_index = i
                break
            # If it's not a control flow and has less indentation, we've gone too far
            break
    
    if control_flow_index is None:
        return False
    
    prev_line = lines[control_flow_index].rstrip()
    prev_indent = get_indentation(lines[control_flow_index])
    
    # Check if this is the FIRST custom_log call in the block
    # Look backwards from this custom_log to see if there are any other custom_log calls
    # at the same indentation level before this one
    is_first_custom_log = True
    for i in range(index - 1, control_flow_index, -1):
        check_line = lines[i]
        check_indent = get_indentation(check_line)
        check_stripped = check_line.strip()
        
        # Skip empty lines and comments
        if not check_stripped or check_stripped.startswith('#'):
            continue
        
        # If we've gone back to the control flow line or beyond, we're at the start
        if len(check_indent) <= len(prev_indent):
            break
        
        # If we find another custom_log call at the same indentation level, this is not the first
        if len(check_indent) == len(current_indent) and re.match(r'^\s*custom_log\(', check_line):
            is_first_custom_log = False
            break
    
    if not is_first_custom_log:
        return False
    
    # Now check if all subsequent lines in this block are custom_log calls or empty
    # (until we hit a line with same or less indentation as the control flow line)
    i = index + 1
    found_non_custom_log = False
    while i < len(lines):
        next_line = lines[i]
        next_indent = get_indentation(next_line)
        
        # If we've reached the end of the block (same or less indentation as control flow line)
        if len(next_indent) <= len(prev_indent) and next_line.strip():
            break
        
        # If the line is not empty and not a custom_log call, this block has other statements
        if next_line.strip() and not re.match(r'^\s*custom_log\(', next_line):
            found_non_custom_log = True
            break
        
        i += 1
    
    # If we found non-custom_log statements, this is not the only statement type
    if found_non_custom_log:
        return False
    
    # If we get here, all statements in the block are custom_log calls (or empty)
    # AND this is the first custom_log call in the block
    # So we should replace this one with 'pass' to avoid empty block
    return True

def comment_custom_logs():
    """Comment out custom_log() calls in all Python files."""
    print(f"\n{Colors.BLUE}Commenting out custom_log() calls...{Colors.NC}")
    
    modified_files_count = 0
    total_lines_count = 0
    
    # Paths to skip (keep full logging to avoid syntax issues)
    skip_paths = [
        BUILD_CONTEXT / 'core' / 'modules' / 'user_management_module',
        BUILD_CONTEXT / 'core' / 'modules' / 'analytics_module',
        BUILD_CONTEXT / 'app.py',
    ]
    
    # Find all Python files
    for py_file in BUILD_CONTEXT.rglob('*.py'):
        # Skip known-problematic modules to keep their logging intact
        if any(str(skip_path) in str(py_file) for skip_path in skip_paths):
            continue
        try:
            with open(py_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            modified_lines = []
            file_modified = False
            lines_in_file = 0
            
            for i, line in enumerate(lines):
                # Check if line starts with custom_log( and is not already commented
                if re.match(r'^\s*custom_log\(', line) and not re.match(r'^\s*#', line):
                    indent = get_indentation(line)
                    after_indent = line[len(indent):].lstrip()
                    
                    # Check if this is the only statement in a block
                    should_replace_with_pass = is_only_statement_in_block(lines, i)
                    if should_replace_with_pass:
                        # Replace with: pass  # custom_log(...)
                        new_line = f"{indent}pass  # {after_indent}"
                        modified_lines.append(new_line)
                        file_modified = True
                        lines_in_file += 1
                    else:
                        # Just comment out: add # right before custom_log
                        new_line = f"{indent}#{after_indent}"
                        modified_lines.append(new_line)
                        file_modified = True
                        lines_in_file += 1
                else:
                    modified_lines.append(line)
            
            if file_modified:
                # Write back the modified content
                with open(py_file, 'w', encoding='utf-8') as f:
                    f.writelines(modified_lines)
                
                modified_files.append(py_file)
                modified_files_count += 1
                total_lines_count += lines_in_file
                rel_path = py_file.relative_to(BUILD_CONTEXT)
                print(f"  {Colors.GREEN}✓{Colors.NC} Modified {rel_path} ({lines_in_file} lines)")
        
        except Exception as e:
            print(f"  {Colors.RED}✗{Colors.NC} Error processing {py_file}: {e}")
    
    print(f"{Colors.GREEN}✓ Commented out {total_lines_count} custom_log() calls in {modified_files_count} files{Colors.NC}")

def uncomment_custom_logs():
    """Restore custom_log() calls in all modified files."""
    print(f"\n{Colors.BLUE}Restoring custom_log() calls...{Colors.NC}")
    
    modified_files_count = 0
    total_lines_count = 0
    
    # Process all Python files (in case some were missed)
    for py_file in BUILD_CONTEXT.rglob('*.py'):
        try:
            with open(py_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            modified_lines = []
            file_modified = False
            lines_in_file = 0
            
            for line in lines:
                # Check if line is: pass  # custom_log(...)
                match = re.match(r'^(\s*)pass\s+#\s+(custom_log\(.*)$', line.rstrip())
                if match:
                    indent = match.group(1)
                    custom_log_part = match.group(2)
                    # Restore to: custom_log(...)
                    new_line = f"{indent}{custom_log_part}\n"
                    modified_lines.append(new_line)
                    file_modified = True
                    lines_in_file += 1
                # Check if line is: #custom_log(...)
                elif re.match(r'^\s*#custom_log\(', line):
                    indent = get_indentation(line)
                    # Remove the # to uncomment
                    after_hash = line[len(indent) + 1:]  # Skip indent and #
                    new_line = f"{indent}{after_hash}"
                    modified_lines.append(new_line)
                    file_modified = True
                    lines_in_file += 1
                else:
                    modified_lines.append(line)
            
            if file_modified:
                # Write back the modified content
                with open(py_file, 'w', encoding='utf-8') as f:
                    f.writelines(modified_lines)
                
                modified_files_count += 1
                total_lines_count += lines_in_file
                rel_path = py_file.relative_to(BUILD_CONTEXT)
                print(f"  {Colors.GREEN}✓{Colors.NC} Restored {rel_path} ({lines_in_file} lines)")
        
        except Exception as e:
            print(f"  {Colors.RED}✗{Colors.NC} Error processing {py_file}: {e}")
    
    print(f"{Colors.GREEN}✓ Restored {total_lines_count} custom_log() calls in {modified_files_count} files{Colors.NC}")

def load_env_file(env_path: Path) -> dict:
    """Load environment variables from .env file."""
    env_vars = {}
    if env_path.exists():
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
    return env_vars

def backup_and_update_secrets():
    """Backup local secret values and update with VPS values from .env."""
    print(f"\n{Colors.BLUE}Updating secrets for VPS Docker build...{Colors.NC}")
    
    secrets_dir = PROJECT_ROOT / 'python_base_04' / 'secrets'
    env_file = PROJECT_ROOT / '.env'
    
    # Load VPS values from .env
    vps_env = load_env_file(env_file)
    
    if not vps_env:
        print(f"{Colors.YELLOW}⚠️  No .env file found or empty. Using default VPS values.{Colors.NC}")
        vps_env = {
            'VPS_MONGODB_PORT': '27017',
            'VPS_REDIS_HOST': 'cleco_redis-external',
            'VPS_REDIS_PORT': '6379'
        }
    
    # Secret files to update
    secrets_to_update = {
        'mongodb_port': vps_env.get('VPS_MONGODB_PORT', '27017'),
        'redis_host': vps_env.get('VPS_REDIS_HOST', 'cleco_redis-external'),
        'redis_port': vps_env.get('VPS_REDIS_PORT', '6379')
    }
    
    # Backup and update each secret file
    for secret_name, vps_value in secrets_to_update.items():
        secret_path = secrets_dir / secret_name
        if secret_path.exists():
            # Backup current value
            with open(secret_path, 'r') as f:
                secret_backups[secret_name] = f.read().strip()
            
            # Update with VPS value
            with open(secret_path, 'w') as f:
                f.write(vps_value + '\n')
            
            print(f"  {Colors.GREEN}✓{Colors.NC} Updated {secret_name}: {secret_backups[secret_name]} → {vps_value}")
        else:
            print(f"  {Colors.YELLOW}⚠️  {secret_name} not found, skipping{Colors.NC}")
    
    print(f"{Colors.GREEN}✓ Secrets updated for VPS Docker build{Colors.NC}")

def restore_secrets():
    """Restore local secret values from backup."""
    if not secret_backups:
        return
    
    print(f"\n{Colors.BLUE}Restoring local secret values...{Colors.NC}")
    
    secrets_dir = PROJECT_ROOT / 'python_base_04' / 'secrets'
    
    for secret_name, local_value in secret_backups.items():
        secret_path = secrets_dir / secret_name
        if secret_path.exists():
            with open(secret_path, 'w') as f:
                f.write(local_value + '\n')
            print(f"  {Colors.GREEN}✓{Colors.NC} Restored {secret_name}: {local_value}")
    
    secret_backups.clear()
    print(f"{Colors.GREEN}✓ Local secrets restored{Colors.NC}")

def check_docker():
    """Check if Docker is running."""
    try:
        subprocess.run(['docker', 'info'], 
                      stdout=subprocess.DEVNULL, 
                      stderr=subprocess.DEVNULL, 
                      check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def build_and_push():
    """Build and push the Docker image."""
    full_image_name = f"{DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}"
    
    print(f"\n{Colors.BLUE}Configuration:{Colors.NC}")
    print(f"  Docker Username: {DOCKER_USERNAME}")
    print(f"  Image Name: {IMAGE_NAME}")
    print(f"  Image Tag: {IMAGE_TAG}")
    print(f"  Full Image: {full_image_name}")
    print(f"  Project Root: {PROJECT_ROOT}")
    print(f"  Dockerfile: {DOCKERFILE_PATH}")
    print(f"  Build Context: {BUILD_CONTEXT}")
    print()
    
    # Confirm before proceeding (non-interactive if stdin is not a TTY)
    if sys.stdin.isatty():
        response = input("Proceed with build and push? (y/n): ").strip().lower()
        if response != 'y':
            print(f"{Colors.YELLOW}Build cancelled.{Colors.NC}")
            return False
    else:
        # Non-interactive mode - auto-confirm
        print("Non-interactive mode: Auto-confirming build and push...")
    
    # Build the Docker image
    print(f"\n{Colors.BLUE}Building Docker image...{Colors.NC}")
    build_cmd = [
        'docker', 'build',
        '-f', str(DOCKERFILE_PATH),
        '-t', full_image_name,
        str(BUILD_CONTEXT)
    ]
    
    try:
        subprocess.run(build_cmd, check=True)
        print(f"{Colors.GREEN}✓ Docker image built successfully{Colors.NC}")
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}✗ Docker build failed{Colors.NC}")
        return False
    
    # Tag as latest if a different tag was used
    if IMAGE_TAG != 'latest':
        print(f"\n{Colors.BLUE}Tagging as latest...{Colors.NC}")
        latest_tag = f"{DOCKER_USERNAME}/{IMAGE_NAME}:latest"
        subprocess.run(['docker', 'tag', full_image_name, latest_tag], check=True)
        print(f"{Colors.GREEN}✓ Tagged as latest{Colors.NC}")
    
    # Push to Docker Hub
    print(f"\n{Colors.BLUE}Pushing to Docker Hub...{Colors.NC}")
    try:
        subprocess.run(['docker', 'push', full_image_name], check=True)
        print(f"{Colors.GREEN}✓ Image pushed successfully{Colors.NC}")
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}✗ Push failed. Make sure you're logged in: docker login{Colors.NC}")
        return False
    
    # Push latest tag if different
    if IMAGE_TAG != 'latest':
        print(f"\n{Colors.BLUE}Pushing latest tag...{Colors.NC}")
        latest_tag = f"{DOCKER_USERNAME}/{IMAGE_NAME}:latest"
        try:
            subprocess.run(['docker', 'push', latest_tag], check=True)
            print(f"{Colors.GREEN}✓ Latest tag pushed successfully{Colors.NC}")
        except subprocess.CalledProcessError:
            pass
    
    return True

def main():
    """Main function."""
    print(f"{Colors.BLUE}=== Docker Build and Push Script ==={Colors.NC}\n")
    
    # Check if Docker is running
    if not check_docker():
        print(f"{Colors.RED}Error: Docker is not running. Please start Docker and try again.{Colors.NC}")
        sys.exit(1)
    
    try:
        # Backup and update secrets for VPS Docker build
        backup_and_update_secrets()
        
        # Comment out custom_log calls
        comment_custom_logs()
        
        # Build and push
        success = build_and_push()
        
        if not success:
            # Restore even if build failed
            uncomment_custom_logs()
            restore_secrets()
            sys.exit(1)
        
        # Restore custom_log calls after successful build and push
        uncomment_custom_logs()
        
        # Restore local secret values
        restore_secrets()
        
        print(f"\n{Colors.GREEN}=== Build and Push Complete ==={Colors.NC}")
        print(f"Image available at: {Colors.BLUE}{DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}{Colors.NC}")
        print(f"\nTo use this image, update docker-compose.yml:")
        print(f"  image: {DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}")
        print()
    
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Interrupted. Restoring files...{Colors.NC}")
        uncomment_custom_logs()
        restore_secrets()
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}Error: {e}{Colors.NC}")
        uncomment_custom_logs()
        restore_secrets()
        sys.exit(1)

if __name__ == '__main__':
    main()
