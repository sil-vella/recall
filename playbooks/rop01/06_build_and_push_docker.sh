#!/bin/bash

# Build and Push Docker Image Script
# This script builds the Flask app Docker image and pushes it to Docker Hub

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
DOCKER_USERNAME="${DOCKER_USERNAME:-silvella}"
IMAGE_NAME="cleco_flask_app"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKERFILE_PATH="${PROJECT_ROOT}/python_base_04/Dockerfile"
BUILD_CONTEXT="${PROJECT_ROOT}/python_base_04"

# Function to comment out custom_log lines
comment_custom_logs() {
    echo -e "\n${BLUE}Commenting out custom_log() calls...${NC}"
    local modified_files=0
    local total_lines=0
    
    # Find all Python files and comment out custom_log lines
    while IFS= read -r file; do
        # Use a temporary file for sed operations
        local temp_file="${file}.tmp"
        local file_modified=false
        local lines_in_file=0
        
        # Process file line by line
        while IFS= read -r line || [ -n "$line" ]; do
            # Check if line starts with custom_log( (with optional leading whitespace)
            # and is not already commented
            if [[ "$line" =~ ^[[:space:]]*custom_log\( ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                # Comment out the line, preserving indentation
                echo "#${line}" >> "$temp_file"
                file_modified=true
                ((lines_in_file++))
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$file"
        
        if [ "$file_modified" = true ]; then
            mv "$temp_file" "$file"
            ((modified_files++))
            ((total_lines += lines_in_file))
            echo -e "  ${GREEN}✓${NC} Modified ${file#${BUILD_CONTEXT}/} (${lines_in_file} lines)"
        else
            rm -f "$temp_file"
        fi
    done < <(find "${BUILD_CONTEXT}" -name "*.py" -type f)
    
    echo -e "${GREEN}✓ Commented out ${total_lines} custom_log() calls in ${modified_files} files${NC}"
}

# Function to uncomment custom_log lines
uncomment_custom_logs() {
    echo -e "\n${BLUE}Restoring custom_log() calls...${NC}"
    local modified_files=0
    local total_lines=0
    
    # Find all Python files and uncomment custom_log lines
    while IFS= read -r file; do
        # Use a temporary file for sed operations
        local temp_file="${file}.tmp"
        local file_modified=false
        local lines_in_file=0
        
        # Process file line by line
        while IFS= read -r line || [ -n "$line" ]; do
            # Check if line is a commented custom_log line
            # Pattern: optional whitespace, #, optional whitespace, custom_log(
            if [[ "$line" =~ ^([[:space:]]*)#([[:space:]]*)custom_log\( ]]; then
                # Uncomment: remove the # but keep indentation
                # Extract the leading whitespace and the rest after #
                local indent="${BASH_REMATCH[1]}"
                local after_hash="${line#*#}"
                echo "${indent}${after_hash}" >> "$temp_file"
                file_modified=true
                ((lines_in_file++))
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$file"
        
        if [ "$file_modified" = true ]; then
            mv "$temp_file" "$file"
            ((modified_files++))
            ((total_lines += lines_in_file))
            echo -e "  ${GREEN}✓${NC} Restored ${file#${BUILD_CONTEXT}/} (${lines_in_file} lines)"
        else
            rm -f "$temp_file"
        fi
    done < <(find "${BUILD_CONTEXT}" -name "*.py" -type f)
    
    echo -e "${GREEN}✓ Restored ${total_lines} custom_log() calls in ${modified_files} files${NC}"
}

# Trap to restore custom_log calls on exit (if they were commented)
RESTORE_LOGS=false
trap 'if [ "$RESTORE_LOGS" = true ]; then uncomment_custom_logs; fi' EXIT INT TERM

echo -e "${BLUE}=== Docker Build and Push Script ===${NC}\n"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Check if Docker Hub credentials are set
if [ -z "$DOCKER_USERNAME" ]; then
    echo -e "${YELLOW}Warning: DOCKER_USERNAME not set. Using default: silvella${NC}"
fi

# Check if user is logged in to Docker Hub
if ! docker info | grep -q "Username"; then
    echo -e "${YELLOW}You may need to log in to Docker Hub.${NC}"
    echo -e "${YELLOW}Run: docker login${NC}"
    read -p "Continue anyway? (y/n): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Full image name
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${BLUE}Configuration:${NC}"
echo -e "  Docker Username: ${DOCKER_USERNAME}"
echo -e "  Image Name: ${IMAGE_NAME}"
echo -e "  Image Tag: ${IMAGE_TAG}"
echo -e "  Full Image: ${FULL_IMAGE_NAME}"
echo -e "  Project Root: ${PROJECT_ROOT}"
echo -e "  Dockerfile: ${DOCKERFILE_PATH}"
echo -e "  Build Context: ${BUILD_CONTEXT}"
echo ""

# Confirm before proceeding
read -p "Proceed with build and push? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Build cancelled.${NC}"
    exit 0
fi

# Comment out custom_log calls before building
comment_custom_logs
RESTORE_LOGS=true  # Set flag so we restore on exit

# Build the Docker image
echo -e "\n${BLUE}Building Docker image...${NC}"
BUILD_SUCCESS=false
docker build \
    -f "${DOCKERFILE_PATH}" \
    -t "${FULL_IMAGE_NAME}" \
    "${BUILD_CONTEXT}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
    BUILD_SUCCESS=true
else
    echo -e "${RED}✗ Docker build failed${NC}"
    # Restore custom_log calls even if build failed
    RESTORE_LOGS=false  # Disable trap since we're restoring manually
    uncomment_custom_logs
    exit 1
fi

# Optionally tag as latest if a different tag was used
if [ "$IMAGE_TAG" != "latest" ]; then
    echo -e "\n${BLUE}Tagging as latest...${NC}"
    docker tag "${FULL_IMAGE_NAME}" "${DOCKER_USERNAME}/${IMAGE_NAME}:latest"
    echo -e "${GREEN}✓ Tagged as latest${NC}"
fi

# Push to Docker Hub
echo -e "\n${BLUE}Pushing to Docker Hub...${NC}"
docker push "${FULL_IMAGE_NAME}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Image pushed successfully${NC}"
else
    echo -e "${RED}✗ Push failed. Make sure you're logged in: docker login${NC}"
    exit 1
fi

# If a different tag was used, also push latest
if [ "$IMAGE_TAG" != "latest" ]; then
    echo -e "\n${BLUE}Pushing latest tag...${NC}"
    docker push "${DOCKER_USERNAME}/${IMAGE_NAME}:latest"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Latest tag pushed successfully${NC}"
    fi
fi

# Restore custom_log calls after successful build and push
RESTORE_LOGS=false  # Disable trap since we're restoring manually
uncomment_custom_logs

echo -e "\n${GREEN}=== Build and Push Complete ===${NC}"
echo -e "Image available at: ${BLUE}${FULL_IMAGE_NAME}${NC}"
echo -e "\nTo use this image, update docker-compose.yml:"
echo -e "  image: ${FULL_IMAGE_NAME}"
echo ""
