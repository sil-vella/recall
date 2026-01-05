#!/usr/bin/env python3
"""
Upload Card Back Image Script
This script uploads a card back image to the VPS at /var/www/dutch.reignofplay.com/sponsors/images/card_back.png
It creates the directory structure if it doesn't exist.
"""

import os
import subprocess
import sys
from pathlib import Path

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
VPS_SSH_TARGET = os.environ.get('VPS_SSH_TARGET', 'rop01_user@65.181.125.135')
VPS_SSH_KEY = os.environ.get('VPS_SSH_KEY', os.path.expanduser('~/.ssh/rop01_key'))
REMOTE_IMAGE_DIR = '/var/www/dutch.reignofplay.com/sponsors/images'
REMOTE_IMAGE_PATH = f'{REMOTE_IMAGE_DIR}/card_back.png'
REMOTE_TMP_IMAGE = '/tmp/card_back.png'
DEFAULT_LOCAL_IMAGE_PATH = PROJECT_ROOT / 'sponsors' / 'images' / 'card_back.png'

def check_ssh_key():
    """Check if SSH key exists."""
    key_path = Path(VPS_SSH_KEY)
    if not key_path.exists():
        print(f"{Colors.RED}Error: SSH key not found at {VPS_SSH_KEY}{Colors.NC}")
        print(f"{Colors.YELLOW}Please run 01_setup_ssh_key.sh first to generate the SSH key.{Colors.NC}")
        return False
    return True

def check_local_image(image_path: Path):
    """Check if local image file exists."""
    if not image_path.exists():
        print(f"{Colors.RED}Error: Image file not found at {image_path}{Colors.NC}")
        return False
    
    if not image_path.is_file():
        print(f"{Colors.RED}Error: {image_path} is not a file{Colors.NC}")
        return False
    
    # Check if it's a valid image file (basic check by extension)
    valid_extensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp']
    if image_path.suffix.lower() not in valid_extensions:
        print(f"{Colors.YELLOW}Warning: File extension {image_path.suffix} may not be a valid image format{Colors.NC}")
        print(f"{Colors.YELLOW}Valid extensions: {', '.join(valid_extensions)}{Colors.NC}")
        response = input("Continue anyway? (y/n): ").strip().lower()
        if response != 'y':
            return False
    
    return True

def upload_image(local_image_path: Path):
    """Upload the image to the VPS."""
    print(f"\n{Colors.BLUE}Configuration:{Colors.NC}")
    print(f"  VPS Target: {VPS_SSH_TARGET}")
    print(f"  SSH Key: {VPS_SSH_KEY}")
    print(f"  Local Image: {local_image_path}")
    print(f"  Remote Path: {REMOTE_IMAGE_PATH}")
    print()
    
    # Confirm before proceeding
    if sys.stdin.isatty():
        response = input("Proceed with upload? (y/n): ").strip().lower()
        if response != 'y':
            print(f"{Colors.YELLOW}Upload cancelled.{Colors.NC}")
            return False
    else:
        # Non-interactive mode - auto-confirm
        print("Non-interactive mode: Auto-confirming upload...")
    
    # Step 1: Upload to temporary location
    print(f"\n{Colors.BLUE}Uploading image to temporary location...{Colors.NC}")
    scp_cmd = [
        'scp',
        '-i', VPS_SSH_KEY,
        str(local_image_path),
        f'{VPS_SSH_TARGET}:{REMOTE_TMP_IMAGE}'
    ]
    
    try:
        subprocess.run(scp_cmd, check=True)
        print(f"{Colors.GREEN}✓ Image uploaded to temporary location{Colors.NC}")
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}✗ Upload failed: {e}{Colors.NC}")
        return False
    except FileNotFoundError:
        print(f"{Colors.RED}✗ scp command not found. Please install OpenSSH client.{Colors.NC}")
        return False
    
    # Step 2: Create directory, move file, and set permissions
    print(f"\n{Colors.BLUE}Creating directory structure and moving image...{Colors.NC}")
    ssh_cmd = [
        'ssh',
        '-i', VPS_SSH_KEY,
        VPS_SSH_TARGET,
        f'sudo mkdir -p {REMOTE_IMAGE_DIR} && '
        f'sudo mv {REMOTE_TMP_IMAGE} {REMOTE_IMAGE_PATH} && '
        f'sudo chown www-data:www-data {REMOTE_IMAGE_PATH} && '
        f'sudo chmod 644 {REMOTE_IMAGE_PATH}'
    ]
    
    try:
        subprocess.run(ssh_cmd, check=True)
        print(f"{Colors.GREEN}✓ Image moved to final location and permissions set{Colors.NC}")
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}✗ Failed to move image or set permissions: {e}{Colors.NC}")
        # Try to clean up temp file
        cleanup_cmd = [
            'ssh',
            '-i', VPS_SSH_KEY,
            VPS_SSH_TARGET,
            f'rm -f {REMOTE_TMP_IMAGE}'
        ]
        try:
            subprocess.run(cleanup_cmd, check=False)
        except:
            pass
        return False
    except FileNotFoundError:
        print(f"{Colors.RED}✗ ssh command not found. Please install OpenSSH client.{Colors.NC}")
        return False
    
    print(f"\n{Colors.GREEN}=== Upload Complete ==={Colors.NC}")
    print(f"Image available at: {Colors.BLUE}{REMOTE_IMAGE_PATH}{Colors.NC}")
    print(f"Expected URL: {Colors.BLUE}https://dutch.reignofplay.com/sponsors/images/card_back.png{Colors.NC}")
    print()
    
    return True

def main():
    """Main function."""
    print(f"{Colors.BLUE}=== Card Back Image Upload Script ==={Colors.NC}\n")
    
    # Check if SSH key exists
    if not check_ssh_key():
        sys.exit(1)
    
    # Get local image path from command line argument, default location, or prompt
    if len(sys.argv) > 1:
        local_image_path = Path(sys.argv[1])
    elif DEFAULT_LOCAL_IMAGE_PATH.exists():
        local_image_path = DEFAULT_LOCAL_IMAGE_PATH
        print(f"{Colors.BLUE}Using default image path: {local_image_path}{Colors.NC}\n")
    else:
        print(f"{Colors.YELLOW}Default image not found at: {DEFAULT_LOCAL_IMAGE_PATH}{Colors.NC}")
        image_path_str = input("Enter path to local card back image file: ").strip()
        if not image_path_str:
            print(f"{Colors.RED}Error: No image path provided{Colors.NC}")
            sys.exit(1)
        local_image_path = Path(image_path_str)
    
    # Resolve to absolute path
    local_image_path = local_image_path.resolve()
    
    # Check if local image exists
    if not check_local_image(local_image_path):
        sys.exit(1)
    
    # Upload the image
    success = upload_image(local_image_path)
    
    if not success:
        sys.exit(1)

if __name__ == '__main__':
    main()
