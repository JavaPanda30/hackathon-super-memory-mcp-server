#!/bin/bash
# ============================================================================
# SyntaxRAG Docker Database Initialization Script
# ============================================================================
# This script initializes a fresh SyntaxRAG database in a Docker container
# with all necessary extensions, tables, indexes, and functions.
#
# Prerequisites:
# - Docker and docker-compose installed
# - SyntaxRAG docker-compose.yml in current directory
# - init_docker_db.sql in current directory
#
# Usage: ./init_docker_db.sh
# ============================================================================

set -e  # Exit on any error

# Configuration
CONTAINER_NAME="agent-recall-db"
DB_NAME="agent_recall"
DB_USER="postgres"
INIT_SQL_FILE="init_docker_db.sql"

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

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running! Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Function to start the database container
start_database() {
    print_status "Starting PostgreSQL container..."
    
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        if docker ps -a | grep -q "$CONTAINER_NAME"; then
            print_status "Container exists but is stopped. Starting..."
            docker start "$CONTAINER_NAME"
        else
            print_status "Container doesn't exist. Creating with docker-compose..."
            if [ ! -f "docker-compose.yml" ]; then
                print_error "docker-compose.yml not found!"
                print_status "Please ensure you're in the SyntaxRAG directory with docker-compose.yml"
                exit 1
            fi
            docker-compose up -d
        fi
    else
        print_success "Container is already running"
    fi
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    print_status "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            print_success "PostgreSQL is ready!"
            return 0
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            print_status "Attempt $attempt/$max_attempts - PostgreSQL not ready yet..."
        fi
        sleep 2
        ((attempt++))
    done
    
    print_error "PostgreSQL failed to become ready after $max_attempts attempts"
    return 1
}

# Function to check if database exists and create if needed
ensure_database() {
    print_status "Checking if database '$DB_NAME' exists..."
    
    if docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
        print_success "Database '$DB_NAME' exists"
    else
        print_status "Creating database '$DB_NAME'..."
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"
        print_success "Database created"
    fi
}

# Function to initialize the database
initialize_database() {
    print_status "Initializing SyntaxRAG database schema..."
    
    if [ ! -f "$INIT_SQL_FILE" ]; then
        print_error "Initialization SQL file '$INIT_SQL_FILE' not found!"
        print_status "Please ensure init_docker_db.sql is in the current directory"
        exit 1
    fi
    
    # Execute the initialization SQL
    if docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" < "$INIT_SQL_FILE"; then
        print_success "Database schema initialized successfully"
    else
        print_error "Failed to initialize database schema"
        return 1
    fi
}

# Function to verify the setup
verify_setup() {
    print_status "Verifying database setup..."
    
    # Check extensions
    local extensions=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('vector', 'uuid-ossp', 'pg_trgm', 'btree_gist')")
    
    if [ "$extensions" -eq 4 ]; then
        print_success "All required extensions are installed"
    else
        print_warning "Expected 4 extensions, found $extensions"
    fi
    
    # Check tables
    local tables=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
    
    if [ "$tables" -eq 3 ]; then
        print_success "All required tables are created"
    else
        print_warning "Expected 3 tables, found $tables"
    fi
    
    # Show database stats
    print_status "Database information:"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            'Database size: ' || pg_size_pretty(pg_database_size('$DB_NAME')) as info
        UNION ALL
        SELECT 'Total memories: ' || COUNT(*)::text FROM memories
        UNION ALL  
        SELECT 'PostgreSQL version: ' || version() as info;
    "
}

# Function to show connection info
show_connection_info() {
    print_header "SyntaxRAG Database Ready!"
    
    echo ""
    print_status "Connection Details:"
    echo "  🏠 Host: localhost"
    echo "  🔌 Port: 5433"
    echo "  🗄️  Database: $DB_NAME"
    echo "  👤 User: $DB_USER"
    echo "  🔑 Password: agent_recall_password"
    echo ""
    
    print_status "Environment Configuration:"
    echo "  📐 Embedding Dimension: 1536"
    echo "  🤖 Embedding Model: text-embedding-3-small"
    echo "  🔍 Vector Index: HNSW with cosine similarity"
    echo ""
    
    print_status "Next Steps:"
    echo "  1. ✅ Update your .env file with correct database credentials"
    echo "  2. 🚀 Start your SyntaxRAG MCP server"
    echo "  3. 🧪 Test the recall agent functionality"
    echo ""
    
    print_success "Your SyntaxRAG recall agent database is ready!"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --reset     Drop and recreate the database (WARNING: destroys all data)"
    echo "  --verify    Only verify the setup without making changes"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Initialize the database"
    echo "  $0 --reset      # Reset and initialize the database"
    echo "  $0 --verify     # Verify current setup"
}

# Function to reset database
reset_database() {
    print_warning "⚠️  RESETTING DATABASE - This will destroy all existing data!"
    echo ""
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo ""
    
    if [[ ! $REPLY == "yes" ]]; then
        print_status "Database reset cancelled"
        return 1
    fi
    
    print_status "Dropping and recreating database..."
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"
    print_success "Database reset complete"
}

# Main execution
main() {
    print_header "SyntaxRAG Docker Database Initialization"
    
    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --verify)
            print_status "Verification mode - checking existing setup..."
            ;;
        --reset)
            print_status "Reset mode - will recreate database..."
            ;;
        "")
            print_status "Standard initialization mode..."
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    # Execute main workflow
    check_docker
    start_database
    wait_for_postgres
    
    # Handle reset if requested
    if [[ "${1:-}" == "--reset" ]]; then
        reset_database
    fi
    
    # Skip initialization in verify mode
    if [[ "${1:-}" != "--verify" ]]; then
        ensure_database
        initialize_database
    fi
    
    verify_setup
    show_connection_info
    
    print_header "Database Initialization Complete! 🎉"
}

# Run main function with all arguments
main "$@"
