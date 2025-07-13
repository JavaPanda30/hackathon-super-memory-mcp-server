#!/bin/bash
# ============================================================================
# SyntaxRAG Database Setup Script
# ============================================================================
# This script sets up the complete SyntaxRAG database with all extensions,
# tables, indexes, and functions needed for the recall agent.
#
# Usage: ./setup_db.sh [--reset]
#   --reset: Drop and recreate the entire database (WARNING: destroys all data)
# ============================================================================

set -e  # Exit on any error

# Configuration
DB_HOST="localhost"
DB_PORT="5433"
DB_NAME="agent_recall"
DB_USER="postgres"
DB_PASSWORD="agent_recall_password"
INIT_SQL_FILE="init_db.sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if PostgreSQL is running
check_postgres() {
    print_status "Checking if PostgreSQL is running..."
    if ! docker ps | grep -q "agent-recall-db"; then
        print_error "PostgreSQL container 'agent-recall-db' is not running!"
        print_status "Starting PostgreSQL container..."
        docker-compose up -d
        sleep 5
    else
        print_success "PostgreSQL container is running"
    fi
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    print_status "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec agent-recall-db pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            print_success "PostgreSQL is ready!"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts - PostgreSQL not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    print_error "PostgreSQL failed to become ready after $max_attempts attempts"
    return 1
}

# Function to execute SQL file
execute_sql() {
    local sql_file="$1"
    print_status "Executing SQL file: $sql_file"
    
    if [ ! -f "$sql_file" ]; then
        print_error "SQL file '$sql_file' not found!"
        return 1
    fi
    
    # Execute the SQL file using docker exec
    if docker exec -i agent-recall-db psql -U "$DB_USER" -d "$DB_NAME" < "$sql_file"; then
        print_success "SQL file executed successfully"
        return 0
    else
        print_error "Failed to execute SQL file"
        return 1
    fi
}

# Function to reset database
reset_database() {
    print_warning "RESETTING DATABASE - This will destroy all existing data!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Database reset cancelled"
        return 1
    fi
    
    print_status "Dropping and recreating database..."
    docker exec agent-recall-db psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
    docker exec agent-recall-db psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"
    print_success "Database reset complete"
}

# Function to check database status
check_database_status() {
    print_status "Checking database status..."
    
    # Check if database exists
    if docker exec agent-recall-db psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
        print_success "Database '$DB_NAME' exists"
        
        # Check tables
        local table_count=$(docker exec agent-recall-db psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
        print_status "Found $table_count tables in database"
        
        # Check extensions
        print_status "Installed extensions:"
        docker exec agent-recall-db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector', 'uuid-ossp', 'pg_trgm', 'btree_gist');"
        
    else
        print_warning "Database '$DB_NAME' does not exist"
        return 1
    fi
}

# Function to create database if it doesn't exist
create_database_if_needed() {
    if ! docker exec agent-recall-db psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
        print_status "Creating database '$DB_NAME'..."
        docker exec agent-recall-db psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"
        print_success "Database created"
    else
        print_status "Database '$DB_NAME' already exists"
    fi
}

# Function to test connection
test_connection() {
    print_status "Testing database connection..."
    if docker exec agent-recall-db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" >/dev/null 2>&1; then
        print_success "Database connection successful"
        return 0
    else
        print_error "Failed to connect to database"
        return 1
    fi
}

# Main execution
main() {
    echo "============================================================================"
    echo "                    SyntaxRAG Database Setup Script"
    echo "============================================================================"
    
    # Check for reset flag
    if [[ "$1" == "--reset" ]]; then
        check_postgres
        wait_for_postgres
        reset_database
    fi
    
    # Start PostgreSQL if needed
    check_postgres
    
    # Wait for PostgreSQL to be ready
    wait_for_postgres
    
    # Create database if needed
    create_database_if_needed
    
    # Test connection
    test_connection
    
    # Execute initialization SQL
    if [ -f "$INIT_SQL_FILE" ]; then
        execute_sql "$INIT_SQL_FILE"
    else
        print_error "Initialization SQL file '$INIT_SQL_FILE' not found!"
        print_status "Please make sure init_db.sql is in the same directory as this script"
        exit 1
    fi
    
    # Check final status
    check_database_status
    
    echo ""
    echo "============================================================================"
    print_success "SyntaxRAG Database Setup Complete!"
    echo "============================================================================"
    print_status "Database is ready for the SyntaxRAG recall agent"
    print_status "Connection details:"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
    echo ""
    print_status "Next steps:"
    echo "  1. Update your .env file with the correct database credentials"
    echo "  2. Start the SyntaxRAG MCP server"
    echo "  3. Test the recall agent functionality"
    echo "============================================================================"
}

# Run main function with all arguments
main "$@"
