#!/usr/bin/env python3
"""
Build and Push Docker Image Script
This script builds the Flask app Docker image and pushes it to Docker Hub.
Before build, it sets LOGGING_SWITCH = False where assignments are True (production-quiet).
custom_log(...) calls are left intact so multi-line calls cannot be broken by naive commenting.
"""

import os
import re
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
DOCKER_USERNAME = os.environ.get('DOCKER_USERNAME', 'silvella')
IMAGE_NAME = 'dutch_flask_app'
IMAGE_TAG = os.environ.get('IMAGE_TAG', 'latest')
DOCKERFILE_PATH = PROJECT_ROOT / 'python_base_04' / 'Dockerfile'
BUILD_CONTEXT = PROJECT_ROOT / 'python_base_04'

# Original file contents for files we modified (path -> text)
LOGGING_SWITCH_BACKUP: dict[Path, str] = {}

# Match a line that is only: optional indent, LOGGING_SWITCH = False, optional trailing comment/whitespace
_ASSIGN_TRUE_LINE = re.compile(r'^(\s*)(LOGGING_SWITCH\s*=\s*)True(\s*(?:#.*)?)$')


def iter_docker_context_py_files():
    """Python files under the Docker build context; skip vendored bundles."""
    for py_file in BUILD_CONTEXT.rglob('*.py'):
        parts = py_file.parts
        if 'libs' in parts or '__pycache__' in parts:
            continue
        yield py_file


def disable_python_logging_switches() -> None:
    """Set LOGGING_SWITCH = False on lines that assign True (backup originals first)."""
    print(f"\n{Colors.BLUE}Setting LOGGING_SWITCH = False for Docker build...{Colors.NC}")

    modified_count = 0
    line_changes = 0

    for py_file in iter_docker_context_py_files():
        try:
            with open(py_file, 'r', encoding='utf-8') as f:
                original = f.read()
        except OSError as e:
            print(f"  {Colors.RED}✗{Colors.NC} Could not read {py_file}: {e}")
            continue

        lines = original.splitlines(keepends=True)
        new_lines: list[str] = []
        file_changed = False

        for line in lines:
            # Leave full-line comments untouched
            stripped_left = line.lstrip()
            if stripped_left.startswith('#'):
                new_lines.append(line)
                continue

            body = line.rstrip('\n\r')
            nl = line[len(body) :]
            m = _ASSIGN_TRUE_LINE.match(body)
            if m:
                new_body = f"{m.group(1)}{m.group(2)}False{m.group(3)}"
                new_lines.append(new_body + nl)
                file_changed = True
                line_changes += 1
            else:
                new_lines.append(line)

        if not file_changed:
            continue

        new_text = ''.join(new_lines)
        LOGGING_SWITCH_BACKUP[py_file] = original
        try:
            with open(py_file, 'w', encoding='utf-8') as f:
                f.write(new_text)
        except OSError as e:
            print(f"  {Colors.RED}✗{Colors.NC} Could not write {py_file}: {e}")
            # Put original back in memory backup only; try restore
            del LOGGING_SWITCH_BACKUP[py_file]
            continue

        modified_count += 1
        rel = py_file.relative_to(BUILD_CONTEXT)
        print(f"  {Colors.GREEN}✓{Colors.NC} {rel}")

    if modified_count == 0:
        print(
            f"{Colors.YELLOW}No LOGGING_SWITCH = False assignments found "
            f"(already False / Config-driven).{Colors.NC}"
        )
    else:
        print(
            f"{Colors.GREEN}✓ Updated LOGGING_SWITCH in {modified_count} file(s) "
            f"({line_changes} line(s)){Colors.NC}"
        )


def restore_python_logging_switches() -> None:
    """Restore sources from backup after build."""
    if not LOGGING_SWITCH_BACKUP:
        return

    print(f"\n{Colors.BLUE}Restoring LOGGING_SWITCH assignments...{Colors.NC}")

    for py_file, original in list(LOGGING_SWITCH_BACKUP.items()):
        try:
            with open(py_file, 'w', encoding='utf-8') as f:
                f.write(original)
            rel = py_file.relative_to(BUILD_CONTEXT)
            print(f"  {Colors.GREEN}✓{Colors.NC} {rel}")
        except OSError as e:
            print(f"  {Colors.RED}✗{Colors.NC} Could not restore {py_file}: {e}")

    LOGGING_SWITCH_BACKUP.clear()
    print(f"{Colors.GREEN}✓ Restore complete{Colors.NC}")


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
    except subprocess.CalledProcessError:
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
    except subprocess.CalledProcessError:
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
        disable_python_logging_switches()

        success = build_and_push()

        if not success:
            sys.exit(1)

        print(f"\n{Colors.GREEN}=== Build and Push Complete ==={Colors.NC}")
        print(f"Image available at: {Colors.BLUE}{DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}{Colors.NC}")
        print(f"\nTo use this image, update docker-compose.yml:")
        print(f"  image: {DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}")
        print()

    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Interrupted.{Colors.NC}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}Error: {e}{Colors.NC}")
        sys.exit(1)
    finally:
        restore_python_logging_switches()


if __name__ == '__main__':
    main()
