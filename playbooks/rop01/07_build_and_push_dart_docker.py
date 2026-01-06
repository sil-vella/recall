#!/usr/bin/env python3
"""
Build and Push Docker Image Script for Dart Game Server
This script builds the Dart WebSocket server Docker image and pushes it to Docker Hub.
"""

import os
import subprocess
import sys
from pathlib import Path


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent

# Configuration
DOCKER_USERNAME = os.environ.get("DOCKER_USERNAME", "silvella")
IMAGE_NAME = "dutch_dart_game_server"
IMAGE_TAG = os.environ.get("IMAGE_TAG", "latest")
DOCKERFILE_PATH = PROJECT_ROOT / "dart_bkend_base_01" / "Dockerfile"
BUILD_CONTEXT = PROJECT_ROOT / "dart_bkend_base_01"


def disable_logging_switch() -> None:
    """Force LOGGING_SWITCH = false in all Dart source files before build."""
    print(f"\n{Colors.BLUE}Disabling LOGGING_SWITCH in Dart sources...{Colors.NC}")
    replaced_files = 0
    replaced_occurrences = 0

    # Predefined variable value to avoid accidentally replacing other 'true' values
    logging_switch_variable_value = "true"

    for dart_file in BUILD_CONTEXT.rglob("*.dart"):
        try:
            text = dart_file.read_text(encoding="utf-8")
            original_text = text
            # Replace LOGGING_SWITCH = false with LOGGING_SWITCH = false
            new_text = text.replace(f"LOGGING_SWITCH = {logging_switch_variable_value}", "LOGGING_SWITCH = false")
            # Also handle const bool LOGGING_SWITCH = false
            new_text = new_text.replace(f"const bool LOGGING_SWITCH = {logging_switch_variable_value}", "const bool LOGGING_SWITCH = false")
            # Also handle static const bool LOGGING_SWITCH = false
            new_text = new_text.replace(f"static const bool LOGGING_SWITCH = {logging_switch_variable_value}", "static const bool LOGGING_SWITCH = false")
            
            if new_text != original_text:
                dart_file.write_text(new_text, encoding="utf-8")
                occurrences = original_text.count(f"LOGGING_SWITCH = {logging_switch_variable_value}") + original_text.count(f"const bool LOGGING_SWITCH = {logging_switch_variable_value}") + original_text.count(f"static const bool LOGGING_SWITCH = {logging_switch_variable_value}")
                replaced_occurrences += occurrences
                replaced_files += 1
                rel = dart_file.relative_to(BUILD_CONTEXT)
                print(f"  {Colors.GREEN}✓{Colors.NC} Updated {rel} ({occurrences} occurrence(s))")
        except Exception as e:
            rel = dart_file.relative_to(BUILD_CONTEXT)
            print(f"  {Colors.RED}✗{Colors.NC} Error processing {rel}: {e}")

    if replaced_files == 0:
        print(f"{Colors.YELLOW}No LOGGING_SWITCH = {logging_switch_variable_value} found in Dart sources (already disabled or not present).{Colors.NC}")
    else:
        print(
            f"{Colors.GREEN}✓ Disabled LOGGING_SWITCH in {replaced_occurrences} "
            f"place(s) across {replaced_files} file(s){Colors.NC}"
        )


def check_docker() -> bool:
    """Check if Docker is running."""
    try:
        subprocess.run(
            ["docker", "info"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def build_and_push() -> bool:
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

    if not DOCKERFILE_PATH.exists():
        print(f"{Colors.RED}Error: Dockerfile not found at {DOCKERFILE_PATH}{Colors.NC}")
        return False

    # Confirm before proceeding (non-interactive if stdin is not a TTY)
    if sys.stdin.isatty():
        response = input("Proceed with build and push? (y/n): ").strip().lower()
        if response != "y":
            print(f"{Colors.YELLOW}Build cancelled.{Colors.NC}")
            return False
    else:
        print("Non-interactive mode: Auto-confirming build and push...")

    # Build the Docker image
    print(f"\n{Colors.BLUE}Building Dart Docker image...{Colors.NC}")
    build_cmd = [
        "docker",
        "build",
        "-f",
        str(DOCKERFILE_PATH),
        "-t",
        full_image_name,
        str(BUILD_CONTEXT),
    ]

    try:
        subprocess.run(build_cmd, check=True)
        print(f"{Colors.GREEN}✓ Docker image built successfully{Colors.NC}")
    except subprocess.CalledProcessError:
        print(f"{Colors.RED}✗ Docker build failed{Colors.NC}")
        return False

    # Tag as latest if a different tag was used
    if IMAGE_TAG != "latest":
        print(f"\n{Colors.BLUE}Tagging as latest...{Colors.NC}")
        latest_tag = f"{DOCKER_USERNAME}/{IMAGE_NAME}:latest"
        subprocess.run(["docker", "tag", full_image_name, latest_tag], check=True)
        print(f"{Colors.GREEN}✓ Tagged as latest{Colors.NC}")

    # Push to Docker Hub
    print(f"\n{Colors.BLUE}Pushing to Docker Hub...{Colors.NC}")
    try:
        subprocess.run(["docker", "push", full_image_name], check=True)
        print(f"{Colors.GREEN}✓ Image pushed successfully{Colors.NC}")
    except subprocess.CalledProcessError:
        print(
            f"{Colors.RED}✗ Push failed. Make sure you're logged in: docker login{Colors.NC}"
        )
        return False

    # Push latest tag if different
    if IMAGE_TAG != "latest":
        print(f"\n{Colors.BLUE}Pushing latest tag...{Colors.NC}")
        latest_tag = f"{DOCKER_USERNAME}/{IMAGE_NAME}:latest"
        try:
            subprocess.run(["docker", "push", latest_tag], check=True)
            print(f"{Colors.GREEN}✓ Latest tag pushed successfully{Colors.NC}")
        except subprocess.CalledProcessError:
            pass

    return True


def main() -> None:
    print(f"{Colors.BLUE}=== Dart Docker Build and Push Script ==={Colors.NC}\n")

    # Ensure noisy logging is disabled in the built image
    disable_logging_switch()

    if not check_docker():
        print(
            f"{Colors.RED}Error: Docker is not running. Please start Docker and try again.{Colors.NC}"
        )
        sys.exit(1)

    success = build_and_push()
    if not success:
        sys.exit(1)

    full_image_name = f"{DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}"
    print(f"\n{Colors.GREEN}=== Build and Push Complete ==={Colors.NC}")
    print(
        f"Image available at: {Colors.BLUE}{full_image_name}{Colors.NC}"
    )
    print("\nTo use this image, update docker-compose.yml:")
    print(f"  image: {DOCKER_USERNAME}/{IMAGE_NAME}:{IMAGE_TAG}")
    print()


if __name__ == "__main__":
    main()
