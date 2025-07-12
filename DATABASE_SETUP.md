# SyntaxRAG Database Initialization

This directory contains scripts and SQL files to initialize a fresh PostgreSQL database for the SyntaxRAG recall agent system.

## Files

### `init_docker_db.sql`
Complete PostgreSQL initialization script that creates:
- **Extensions**: pgvector, uuid-ossp, pg_trgm, btree_gist
- **Tables**: memories, memory_tags, memory_metadata
- **Indexes**: HNSW vector index, full-text search, performance indexes
- **Functions**: Semantic search, text search, triggers
- **Views**: Statistics and aggregated data views
- **Configuration**: Optimized settings for vector operations

### `init_docker_db.sh`
Automated shell script that:
- Starts PostgreSQL Docker container
- Waits for database to be ready
- Creates database if needed
- Executes the initialization SQL
- Verifies the setup
- Shows connection details

## Quick Start

### 1. Basic Initialization
```bash
# Start fresh database with all schema
./init_docker_db.sh
```

### 2. Reset Database (WARNING: Destroys all data)
```bash
# Drop and recreate everything
./init_docker_db.sh --reset
```

### 3. Verify Existing Setup
```bash
# Check current database status
./init_docker_db.sh --verify
```

## Manual Setup

If you prefer to run the SQL manually:

```bash
# Start the PostgreSQL container
docker-compose up -d

# Wait for it to be ready
docker exec agent-recall-db pg_isready -U postgres

# Create database if needed
docker exec agent-recall-db psql -U postgres -c "CREATE DATABASE agent_recall;"

# Run the initialization SQL
docker exec -i agent-recall-db psql -U postgres -d agent_recall < init_docker_db.sql
```

## Configuration

The database is configured for:
- **Host**: localhost
- **Port**: 5433
- **Database**: agent_recall
- **User**: postgres
- **Password**: agent_recall_password
- **Embedding Dimension**: 1536 (text-embedding-3-small)

## Environment Setup

Make sure your `.env` file contains:
```properties
POSTGRES_HOST=localhost
POSTGRES_PORT=5433
POSTGRES_DB=agent_recall
POSTGRES_USER=postgres
POSTGRES_PASSWORD=agent_recall_password
EMBEDDING_DIMENSION=1536
EMBEDDING_MODEL="text-embedding-3-small"
```

## Verification

After initialization, you can verify the setup:

```sql
-- Check extensions
SELECT extname, extversion FROM pg_extension 
WHERE extname IN ('vector', 'uuid-ossp', 'pg_trgm', 'btree_gist');

-- Check tables
SELECT tablename FROM pg_tables WHERE schemaname = 'public';

-- Check memory count
SELECT COUNT(*) FROM memories;

-- Test vector search function
SELECT * FROM search_memories_semantic(
    ARRAY[0.1, 0.2, 0.3] || ARRAY(SELECT 0.0 FROM generate_series(1, 1533)),
    0.1, 
    5
);
```

## Features

### Vector Search
- **HNSW Index**: High-performance vector similarity search
- **Cosine Distance**: Semantic similarity matching
- **Configurable Thresholds**: Adjustable similarity requirements

### Full-Text Search
- **Multi-language Support**: English text processing
- **Weighted Ranking**: Heading > Summary > Context priority
- **Trigram Matching**: Fuzzy text matching capabilities

### Flexible Metadata
- **Tag System**: Categorical memory organization
- **JSON Metadata**: Flexible key-value storage
- **Time-based Filtering**: Chronological memory retrieval

### Performance Optimization
- **Optimized Indexes**: Fast query performance
- **Connection Pooling Ready**: Production-ready configuration
- **Memory Efficient**: Optimized for Docker containers

## Troubleshooting

### Container Not Starting
```bash
# Check if container exists
docker ps -a | grep agent-recall-db

# Check logs
docker logs agent-recall-db

# Restart container
docker-compose restart
```

### Permission Issues
```bash
# Make script executable
chmod +x init_docker_db.sh

# Check Docker permissions
docker info
```

### Database Connection Issues
```bash
# Test connection
docker exec agent-recall-db psql -U postgres -d agent_recall -c "SELECT version();"

# Check if database exists
docker exec agent-recall-db psql -U postgres -c "\l"
```

### Vector Extension Issues
```bash
# Verify pgvector installation
docker exec agent-recall-db psql -U postgres -d agent_recall -c "SELECT * FROM pg_extension WHERE extname='vector';"

# Check vector operations
docker exec agent-recall-db psql -U postgres -d agent_recall -c "SELECT '[1,2,3]'::vector;"
```

## Development

For development and testing:

```bash
# Start with sample data (uncomment section in SQL file)
# Edit init_docker_db.sql and uncomment the sample data section

# Run initialization with reset
./init_docker_db.sh --reset

# Connect to database for manual testing
docker exec -it agent-recall-db psql -U postgres -d agent_recall
```

## Production Notes

- The initialization script includes performance optimizations
- Settings require PostgreSQL restart to take effect
- Consider adjusting memory settings based on your hardware
- Monitor vector index performance and rebuild if needed

---

🚀 **Your SyntaxRAG recall agent database is ready for storing and retrieving memories!**
