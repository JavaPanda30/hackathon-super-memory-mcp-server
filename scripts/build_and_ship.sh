#!/bin/bash
# ============================================================================
# SyntaxRAG Docker Build and Ship Script
# ============================================================================
# This script builds the SyntaxRAG Docker image and provides options for
# shipping it to different machines or registries.
#
# Usage:
#   ./build_and_ship.sh [OPTIONS]
#
# Options:
#   --build-only        Only build the image locally
#   --save              Build and save image to tar file
#   --registry REGISTRY Push to specified registry
#   --version VERSION   Tag with specific version (default: latest)
#   --platform PLATFORM Build for specific platform (e.g., linux/amd64)
#   --help              Show this help message
# ============================================================================

set -e  # Exit on error

# Configuration
DEFAULT_IMAGE_NAME="syntaxrag"
DEFAULT_VERSION="latest"
DEFAULT_PLATFORM="linux/amd64"
DOCKERHUB_IMAGE_NAME="suyashtaza/super-memory-mcp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "${CYAN}============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================================${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "SyntaxRAG Docker Build and Ship Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build-only        Only build the image locally"
    echo "  --save              Build and save image to tar file"
    echo "  --registry REGISTRY Push to specified registry (e.g., docker.io/username, ghcr.io/username)"
    echo "  --push-dockerhub    Push to Docker Hub as suyashtaza/super-memory-mcp"
    echo "  --version VERSION   Tag with specific version (default: latest)"
    echo "  --platform PLATFORM Build for specific platform (default: linux/amd64)"
    echo "  --multi-arch        Build for multiple architectures (amd64, arm64)"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --build-only                                    # Build locally only"
    echo "  $0 --save --version v1.0.0                         # Build and save to tar file"
    echo "  $0 --registry docker.io/username --version v1.0.0  # Build and push to Docker Hub"
    echo "  $0 --push-dockerhub --version v1.0.0               # Build and push to suyashtaza/super-memory-mcp"
    echo "  $0 --registry ghcr.io/username --multi-arch        # Build multi-arch and push to GitHub"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running!"
        exit 1
    fi
    
    # Check if Dockerfile exists
    if [ ! -f "Dockerfile" ]; then
        print_error "Dockerfile not found in current directory!"
        exit 1
    fi
    
    # Check if requirements.txt exists
    if [ ! -f "requirements.txt" ]; then
        print_error "requirements.txt not found!"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to build Docker image
build_image() {
    local image_name="$1"
    local version="$2"
    local platform="$3"
    local multi_arch="$4"
    
    print_status "Building Docker image: ${image_name}:${version}"
    
    if [ "$multi_arch" = true ]; then
        print_status "Building for multiple architectures (amd64, arm64)..."
        
        # Setup buildx if not already done
        if ! docker buildx ls | grep -q "multiarch"; then
            print_status "Setting up Docker buildx for multi-architecture builds..."
            docker buildx create --name multiarch --use
            docker buildx inspect --bootstrap
        else
            docker buildx use multiarch
        fi
        
        # Build for multiple platforms
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --tag "${image_name}:${version}" \
            --tag "${image_name}:latest" \
            .
    else
        print_status "Building for platform: $platform"
        docker build \
            --platform "$platform" \
            --tag "${image_name}:${version}" \
            --tag "${image_name}:latest" \
            .
    fi
    
    print_success "Image built successfully"
}

# Function to save image to tar file
save_image() {
    local image_name="$1"
    local version="$2"
    
    local output_file="${image_name}-${version}.tar"
    
    print_status "Saving image to: $output_file"
    docker save "${image_name}:${version}" > "$output_file"
    
    local file_size=$(du -h "$output_file" | cut -f1)
    print_success "Image saved to $output_file (Size: $file_size)"
    
    print_status "To load this image on another machine, run:"
    echo "  docker load < $output_file"
}

# Function to push to registry
push_to_registry() {
    local image_name="$1"
    local version="$2"
    local registry="$3"
    local multi_arch="$4"
    
    local registry_image="${registry}/${image_name}"
    
    print_status "Pushing to registry: $registry"
    
    if [ "$multi_arch" = true ]; then
        print_status "Pushing multi-architecture image..."
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --tag "${registry_image}:${version}" \
            --tag "${registry_image}:latest" \
            --push \
            .
    else
        # Tag for registry
        docker tag "${image_name}:${version}" "${registry_image}:${version}"
        docker tag "${image_name}:latest" "${registry_image}:latest"
        
        # Push to registry
        docker push "${registry_image}:${version}"
        docker push "${registry_image}:latest"
    fi
    
    print_success "Image pushed successfully"
    print_status "To pull this image on another machine, run:"
    echo "  docker pull ${registry_image}:${version}"
}

# Function to show image info
show_image_info() {
    local image_name="$1"
    local version="$2"
    
    print_status "Image information:"
    docker images "${image_name}:${version}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
    
    print_status "Image layers:"
    docker history "${image_name}:${version}" --format "table {{.CreatedBy}}\t{{.Size}}" | head -10
}

# Function to test image
test_image() {
    local image_name="$1"
    local version="$2"
    
    print_status "Testing image..."
    
    # Test if image can start
    local container_id=$(docker run -d --rm "${image_name}:${version}" sleep 10)
    
    if [ $? -eq 0 ]; then
        print_success "Image can start successfully"
        docker stop "$container_id" >/dev/null 2>&1
    else
        print_error "Image failed to start"
        return 1
    fi
}

# Main function
main() {
    local build_only=false
    local save_image_flag=false
    local registry=""
    local version="$DEFAULT_VERSION"
    local platform="$DEFAULT_PLATFORM"
    local multi_arch=false
    local image_name="$DEFAULT_IMAGE_NAME"
    local push_dockerhub=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                build_only=true
                shift
                ;;
            --save)
                save_image_flag=true
                shift
                ;;
            --registry)
                registry="$2"
                shift 2
                ;;
            --push-dockerhub)
                push_dockerhub=true
                shift
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            --platform)
                platform="$2"
                shift 2
                ;;
            --multi-arch)
                multi_arch=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Main execution
    print_header "SyntaxRAG Docker Build and Ship"
    
    # Check prerequisites
    check_prerequisites
    
    # Build image
    build_image "$image_name" "$version" "$platform" "$multi_arch"
    
    # Test image
    if [ "$multi_arch" != true ]; then
        test_image "$image_name" "$version"
    fi
    
    # Show image info
    if [ "$multi_arch" != true ]; then
        show_image_info "$image_name" "$version"
    fi
    
    # Handle shipping options
    if [ "$save_image_flag" = true ]; then
        save_image "$image_name" "$version"
    fi
    
    # Push to Docker Hub shortcut
    if [ "$push_dockerhub" = true ]; then
        push_to_registry "$image_name" "$version" "$DOCKERHUB_IMAGE_NAME" "$multi_arch"
    fi

    if [ -n "$registry" ]; then
        push_to_registry "$image_name" "$version" "$registry" "$multi_arch"
    fi
    
    # Final instructions
    print_header "Build Complete!"
    
    if [ "$build_only" = true ]; then
        print_success "Image built locally: ${image_name}:${version}"
        print_status "To run the image:"
        echo "  docker-compose up -d"
        echo "  # or"
        echo "  docker run -d --env-file .env -p 8000:8000 ${image_name}:${version}"
    fi
    
    if [ "$save_image_flag" = true ]; then
        print_status "Image saved to tar file for manual transfer"
    fi
    
    if [ -n "$registry" ]; then
        print_status "Image available in registry: ${registry}/${image_name}:${version}"
    fi
    
    print_status "For deployment instructions, see: DOCKER_SHIPPING_GUIDE.md"
}

# Run main function with all arguments
main "$@"
