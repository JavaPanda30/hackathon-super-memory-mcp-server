#!/bin/bash
# ============================================================================
# SyntaxRAG Docker Deployment Script
# ============================================================================
# This script builds and deploys the SyntaxRAG recall agent system using Docker.
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --build-only    Only build the Docker image, don't deploy
#   --no-cache      Build without using Docker cache
#   --production    Deploy with production profile (includes Nginx)
#   --help          Show this help message
# ============================================================================

set -e  # Exit on any error

# Configuration
IMAGE_NAME="syntaxrag"
IMAGE_TAG="${IMAGE_TAG:-latest}"
COMPOSE_FILE="docker-compose.prod.yml"

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
    echo "  --build-only     Only build the Docker image, don't deploy"
    echo "  --no-cache       Build without using Docker cache"
    echo "  --production     Deploy with production profile (includes Nginx)"
    echo "  --help           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  IMAGE_TAG        Docker image tag (default: latest)"
    echo "  OPENAI_API_KEY   Required: Your OpenAI API key"
    echo ""
    echo "Examples:"
    echo "  $0                    # Standard deployment"
    echo "  $0 --build-only       # Only build the image"
    echo "  $0 --production       # Production deployment with Nginx"
    echo "  IMAGE_TAG=v1.0 $0     # Deploy with specific tag"
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
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        print_error "docker-compose is not installed!"
        exit 1
    fi
    
    # Check if required files exist
    local required_files=("Dockerfile" "$COMPOSE_FILE" "init_docker_db.sql")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file '$file' not found!"
            exit 1
        fi
    done
    
    print_success "All prerequisites met"
}

# Function to check environment variables
check_environment() {
    print_status "Checking environment configuration..."
    
    # Check for .env file
    if [ ! -f ".env" ]; then
        if [ -f "env.example" ]; then
            print_warning ".env file not found, but env.example exists"
            print_status "Please copy env.example to .env and configure your settings:"
            echo "  cp env.example .env"
            echo "  nano .env  # Edit with your settings"
            exit 1
        else
            print_warning "No .env file found. Using environment variables."
        fi
    else
        print_success ".env file found"
    fi
    
    # Check critical environment variables
    if [ -z "$OPENAI_API_KEY" ] && ! grep -q "OPENAI_API_KEY=" .env 2>/dev/null; then
        print_error "OPENAI_API_KEY is required but not set!"
        print_status "Please set it in .env file or as environment variable"
        exit 1
    fi
    
    print_success "Environment configuration looks good"
}

# Function to build Docker image
build_image() {
    local build_args=""
    
    if [[ "$1" == "--no-cache" ]]; then
        build_args="--no-cache"
        print_status "Building Docker image without cache..."
    else
        print_status "Building Docker image..."
    fi
    
    # Build the image
    if docker build $build_args -t "${IMAGE_NAME}:${IMAGE_TAG}" .; then
        print_success "Docker image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi
    
    # Show image size
    local image_size=$(docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "table {{.Size}}" | tail -n 1)
    print_status "Image size: $image_size"
}

# Function to deploy services
deploy_services() {
    local production_mode="$1"
    
    print_status "Deploying SyntaxRAG services..."
    
    # Set up compose command
    local compose_cmd="docker-compose -f $COMPOSE_FILE"
    
    if [[ "$production_mode" == "true" ]]; then
        print_status "Deploying in production mode (with Nginx)..."
        compose_cmd="$compose_cmd --profile production"
    fi
    
    # Stop existing services
    print_status "Stopping existing services..."
    $compose_cmd down
    
    # Start services
    print_status "Starting services..."
    if $compose_cmd up -d; then
        print_success "Services deployed successfully"
    else
        print_error "Failed to deploy services"
        exit 1
    fi
    
    # Wait for services to be healthy
    print_status "Waiting for services to be healthy..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose -f $COMPOSE_FILE ps | grep -q "healthy"; then
            print_success "Services are healthy!"
            break
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            print_status "Attempt $attempt/$max_attempts - waiting for services..."
        fi
        
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_warning "Services may not be fully healthy yet. Check logs with:"
        echo "  docker-compose -f $COMPOSE_FILE logs"
    fi
}

# Function to show deployment status
show_status() {
    print_header "SyntaxRAG Deployment Status"
    
    # Show running containers
    print_status "Running containers:"
    docker-compose -f $COMPOSE_FILE ps
    
    echo ""
    
    # Show service URLs
    print_status "Service URLs:"
    local syntaxrag_port=$(grep "SYNTAXRAG_PORT" .env 2>/dev/null | cut -d'=' -f2 || echo "8000")
    local postgres_port=$(grep "POSTGRES_PORT" .env 2>/dev/null | cut -d'=' -f2 || echo "5433")
    
    echo "  🤖 SyntaxRAG MCP Server: http://localhost:${syntaxrag_port}"
    echo "  📊 Health Check: http://localhost:${syntaxrag_port}/health"
    echo "  🗄️  PostgreSQL Database: localhost:${postgres_port}"
    
    echo ""
    
    # Show logs command
    print_status "Useful commands:"
    echo "  📋 View logs: docker-compose -f $COMPOSE_FILE logs -f"
    echo "  🔄 Restart: docker-compose -f $COMPOSE_FILE restart"
    echo "  🛑 Stop: docker-compose -f $COMPOSE_FILE down"
    echo "  📈 Monitor: docker stats"
}

# Function to test deployment
test_deployment() {
    print_status "Testing deployment..."
    
    local syntaxrag_port=$(grep "SYNTAXRAG_PORT" .env 2>/dev/null | cut -d'=' -f2 || echo "8000")
    local health_url="http://localhost:${syntaxrag_port}/health"
    
    # Wait a bit for services to start
    sleep 10
    
    # Test health endpoint
    if curl -f -s "$health_url" >/dev/null; then
        print_success "Health check passed!"
        
        # Show health status
        local health_response=$(curl -s "$health_url")
        echo "Health status: $health_response"
    else
        print_warning "Health check failed. Service may still be starting up."
        print_status "You can check the health manually at: $health_url"
    fi
}

# Main execution
main() {
    print_header "SyntaxRAG Docker Deployment"
    
    # Parse command line arguments
    local build_only=false
    local no_cache=false
    local production=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                build_only=true
                shift
                ;;
            --no-cache)
                no_cache=true
                shift
                ;;
            --production)
                production=true
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
    
    # Execute deployment steps
    check_prerequisites
    check_environment
    
    # Build image
    if [[ "$no_cache" == "true" ]]; then
        build_image "--no-cache"
    else
        build_image
    fi
    
    # Deploy if not build-only
    if [[ "$build_only" == "false" ]]; then
        deploy_services "$production"
        show_status
        test_deployment
        
        print_header "Deployment Complete! 🚀"
        print_success "SyntaxRAG recall agent is now running!"
        
        if [[ "$production" == "true" ]]; then
            print_status "Production mode enabled with Nginx reverse proxy"
        fi
        
    else
        print_header "Build Complete! 📦"
        print_success "Docker image ${IMAGE_NAME}:${IMAGE_TAG} is ready"
        print_status "To deploy, run: $0"
    fi
}

# Run main function with all arguments
main "$@"
