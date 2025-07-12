#!/bin/bash
# ============================================================================
# SyntaxRAG Docker Image Builder and Shipper
# ============================================================================
# This script builds the SyntaxRAG Docker image and prepares it for shipping
# to different machines via Docker registry or tar file.
#
# Usage:
#   ./ship.sh [OPTIONS]
#
# Options:
#   --registry REGISTRY    Push to Docker registry (e.g., docker.io/username)
#   --tag TAG             Image tag (default: latest)
#   --tar                 Export as tar file for manual transfer
#   --platforms PLATFORMS Multi-platform build (e.g., linux/amd64,linux/arm64)
#   --help                Show this help message
# ============================================================================

set -e  # Exit on any error

# Configuration
IMAGE_NAME="syntaxrag"
DEFAULT_TAG="latest"
TAR_FILENAME="syntaxrag-docker-image.tar"

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
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --registry REGISTRY    Push to Docker registry (e.g., docker.io/username)"
    echo "  --tag TAG             Image tag (default: latest)"
    echo "  --tar                 Export as tar file for manual transfer"
    echo "  --platforms PLATFORMS Multi-platform build (e.g., linux/amd64,linux/arm64)"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --tar                                    # Export as tar file"
    echo "  $0 --registry docker.io/myuser             # Push to Docker Hub"
    echo "  $0 --registry myregistry.com/myuser --tag v1.0  # Push with custom tag"
    echo "  $0 --platforms linux/amd64,linux/arm64     # Multi-platform build"
    echo ""
    echo "For manual transfer:"
    echo "  1. Run: $0 --tar"
    echo "  2. Copy ${TAR_FILENAME} to target machine"
    echo "  3. On target: docker load < ${TAR_FILENAME}"
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
    
    # Check if required files exist
    local required_files=("Dockerfile" "requirements.txt")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file '$file' not found!"
            exit 1
        fi
    done
    
    print_success "Prerequisites check passed"
}

# Function to build Docker image
build_image() {
    local tag="$1"
    local platforms="$2"
    local registry="$3"
    
    local full_image_name="${IMAGE_NAME}:${tag}"
    
    if [ -n "$registry" ]; then
        full_image_name="${registry}/${IMAGE_NAME}:${tag}"
    fi
    
    print_status "Building Docker image: $full_image_name"
    
    # Build command
    local build_cmd="docker build"
    local build_args=""
    
    # Multi-platform build
    if [ -n "$platforms" ]; then
        print_status "Building for platforms: $platforms"
        
        # Check if buildx is available
        if ! docker buildx version >/dev/null 2>&1; then
            print_error "Docker buildx is required for multi-platform builds!"
            print_status "Install with: docker buildx install"
            exit 1
        fi
        
        # Create buildx builder if needed
        if ! docker buildx ls | grep -q "syntaxrag-builder"; then
            print_status "Creating buildx builder..."
            docker buildx create --name syntaxrag-builder --use
        else
            docker buildx use syntaxrag-builder
        fi
        
        build_cmd="docker buildx build"
        build_args="--platform $platforms"
        
        if [ -n "$registry" ]; then
            build_args="$build_args --push"
        else
            build_args="$build_args --load"
        fi
    fi
    
    # Add build arguments for better caching
    build_args="$build_args --build-arg BUILDKIT_INLINE_CACHE=1"
    
    # Execute build
    if $build_cmd $build_args -t "$full_image_name" .; then
        print_success "Image built successfully: $full_image_name"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi
    
    # Show image information
    if [ -z "$platforms" ] || [ -z "$registry" ]; then
        local image_size=$(docker images "$full_image_name" --format "table {{.Size}}" | tail -n 1)
        print_status "Image size: $image_size"
        
        # Show image layers
        print_status "Image layers:"
        docker history "$full_image_name" --format "table {{.CreatedBy}}\t{{.Size}}" | head -10
    fi
}

# Function to push to registry
push_to_registry() {
    local registry="$1"
    local tag="$2"
    
    local full_image_name="${registry}/${IMAGE_NAME}:${tag}"
    
    print_status "Pushing to registry: $full_image_name"
    
    # Check if logged in to registry
    local registry_host=$(echo "$registry" | cut -d'/' -f1)
    
    if ! docker info | grep -q "Registry"; then
        print_warning "You may need to login to the registry:"
        echo "  docker login $registry_host"
    fi
    
    # Push the image
    if docker push "$full_image_name"; then
        print_success "Image pushed successfully to $full_image_name"
        
        # Show pull command for users
        echo ""
        print_status "To use this image on another machine:"
        echo "  docker pull $full_image_name"
        echo "  docker run -d --name syntaxrag $full_image_name"
        
    else
        print_error "Failed to push image to registry"
        exit 1
    fi
}

# Function to export as tar
export_as_tar() {
    local tag="$1"
    local image_name="${IMAGE_NAME}:${tag}"
    
    print_status "Exporting image as tar file: $TAR_FILENAME"
    
    # Remove existing tar file
    if [ -f "$TAR_FILENAME" ]; then
        rm "$TAR_FILENAME"
    fi
    
    # Export image
    if docker save -o "$TAR_FILENAME" "$image_name"; then
        local file_size=$(du -h "$TAR_FILENAME" | cut -f1)
        print_success "Image exported successfully: $TAR_FILENAME ($file_size)"
        
        echo ""
        print_status "To use this image on another machine:"
        echo "  1. Copy $TAR_FILENAME to the target machine"
        echo "  2. Load the image: docker load < $TAR_FILENAME"
        echo "  3. Run the container: docker run -d --name syntaxrag $image_name"
        
    else
        print_error "Failed to export image as tar"
        exit 1
    fi
}

# Function to create deployment package
create_deployment_package() {
    local tag="$1"
    
    print_status "Creating deployment package..."
    
    local package_name="syntaxrag-deployment-${tag}.tar.gz"
    
    # Create temporary directory
    local temp_dir="syntaxrag-deployment-temp"
    rm -rf "$temp_dir"
    mkdir "$temp_dir"
    
    # Copy necessary files
    cp docker-compose.prod.yml "$temp_dir/"
    cp init_docker_db.sql "$temp_dir/"
    cp env.example "$temp_dir/"
    cp deploy.sh "$temp_dir/"
    
    # Create README for deployment
    cat > "$temp_dir/DEPLOYMENT_README.md" << 'EOF'
# SyntaxRAG Deployment Package

This package contains everything needed to deploy SyntaxRAG on a new machine.

## Quick Start

1. Load the Docker image:
   ```bash
   docker load < syntaxrag-docker-image.tar
   ```

2. Configure environment:
   ```bash
   cp env.example .env
   nano .env  # Edit with your settings
   ```

3. Deploy:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

## Files Included

- `syntaxrag-docker-image.tar` - Docker image
- `docker-compose.prod.yml` - Production deployment configuration
- `init_docker_db.sql` - Database initialization script
- `env.example` - Environment configuration template
- `deploy.sh` - Deployment script
- `DEPLOYMENT_README.md` - This file

## Requirements

- Docker and docker-compose installed
- OpenAI API key
- Available ports: 8000 (SyntaxRAG), 5433 (PostgreSQL)

## Support

For issues and documentation, visit: https://github.com/your-repo/syntaxrag
EOF
    
    # Copy Docker image if it exists
    if [ -f "$TAR_FILENAME" ]; then
        cp "$TAR_FILENAME" "$temp_dir/"
    fi
    
    # Create deployment package
    tar -czf "$package_name" -C . "$temp_dir"
    rm -rf "$temp_dir"
    
    local package_size=$(du -h "$package_name" | cut -f1)
    print_success "Deployment package created: $package_name ($package_size)"
    
    echo ""
    print_status "This package contains everything needed for deployment!"
}

# Function to show shipping options
show_shipping_options() {
    print_header "SyntaxRAG Shipping Options"
    
    echo ""
    print_status "Choose your shipping method:"
    echo ""
    echo "🐳 Docker Registry (Recommended for CI/CD):"
    echo "   $0 --registry docker.io/yourusername"
    echo "   • Automatic updates"
    echo "   • Easy version management"
    echo "   • Requires internet on target machine"
    echo ""
    echo "📦 Tar Export (Good for air-gapped environments):"
    echo "   $0 --tar"
    echo "   • No internet required on target"
    echo "   • Manual file transfer"
    echo "   • Larger file size"
    echo ""
    echo "🔧 Multi-platform (For different architectures):"
    echo "   $0 --platforms linux/amd64,linux/arm64 --registry yourregistry"
    echo "   • Supports ARM and x86 machines"
    echo "   • Requires buildx"
    echo ""
}

# Main execution
main() {
    # Parse command line arguments
    local registry=""
    local tag="$DEFAULT_TAG"
    local export_tar=false
    local platforms=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --registry)
                registry="$2"
                shift 2
                ;;
            --tag)
                tag="$2"
                shift 2
                ;;
            --tar)
                export_tar=true
                shift
                ;;
            --platforms)
                platforms="$2"
                shift 2
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
    
    # Show options if no arguments
    if [ -z "$registry" ] && [ "$export_tar" = false ] && [ -z "$platforms" ]; then
        show_shipping_options
        exit 0
    fi
    
    print_header "SyntaxRAG Docker Image Shipping"
    
    # Execute shipping steps
    check_prerequisites
    
    # Build image
    build_image "$tag" "$platforms" "$registry"
    
    # Handle registry push
    if [ -n "$registry" ] && [ -z "$platforms" ]; then
        push_to_registry "$registry" "$tag"
    fi
    
    # Handle tar export
    if [ "$export_tar" = true ]; then
        export_as_tar "$tag"
        create_deployment_package "$tag"
    fi
    
    print_header "Shipping Complete! 🚢"
    
    if [ -n "$registry" ]; then
        print_success "Image available at: ${registry}/${IMAGE_NAME}:${tag}"
    fi
    
    if [ "$export_tar" = true ]; then
        print_success "Deployment package ready for manual transfer"
    fi
}

# Run main function with all arguments
main "$@"
