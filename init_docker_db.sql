-- ============================================================================
-- SyntaxRAG Initial Database Setup for Docker
-- ============================================================================
-- This script initializes a fresh PostgreSQL database with pgvector for
-- the SyntaxRAG recall agent system.
--
-- Compatible with: pgvector/pgvector:pg16 Docker image
-- Database: agent_recall
-- User: postgres
-- Password: agent_recall_password (as per docker-compose.yml)
--
-- Usage in Docker:
--   docker exec -i agent-recall-db psql -U postgres -d agent_recall < init_docker_db.sql
-- ============================================================================

-- Set client encoding and timezone
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
SET timezone = 'UTC';

-- Display current connection info
SELECT 'Initializing SyntaxRAG database on ' || current_database() || ' at ' || now() AS status;

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

-- Core extensions for vector operations and utilities
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- Text similarity search
CREATE EXTENSION IF NOT EXISTS btree_gist; -- Advanced indexing

SELECT 'Extensions installed successfully' AS status;

-- ============================================================================
-- DROP EXISTING TABLES (for clean setup)
-- ============================================================================

-- Drop existing tables if they exist to ensure clean setup
DROP TABLE IF EXISTS memory_metadata CASCADE;
DROP TABLE IF EXISTS memory_tags CASCADE;
DROP TABLE IF EXISTS memories CASCADE;

SELECT 'Existing tables dropped (if any)' AS status;

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Main memories table with 1536-dimensional embeddings (text-embedding-3-small)
CREATE TABLE memories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    heading TEXT NOT NULL,
    summary TEXT NOT NULL,
    embedding VECTOR(1536) NOT NULL,  -- text-embedding-3-small dimension
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Additional metadata fields
    context TEXT,
    source TEXT DEFAULT 'chat',
    importance_score FLOAT DEFAULT 0.5 CHECK (importance_score >= 0 AND importance_score <= 1),
    
    -- Full text search vector (auto-generated)
    search_vector TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english', COALESCE(heading, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(summary, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(context, '')), 'C')
    ) STORED
);

-- Memory tags for categorization
CREATE TABLE memory_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(memory_id, tag)
);

-- Flexible metadata storage (key-value pairs as JSONB)
CREATE TABLE memory_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(memory_id, key)
);

SELECT 'Tables created successfully' AS status;

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================

-- Vector similarity search index (HNSW for better performance)
-- Note: HNSW is preferred over IVFFlat for smaller datasets and better recall
CREATE INDEX idx_memories_embedding_hnsw 
ON memories USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Time-based indexes for chronological queries
CREATE INDEX idx_memories_created_at ON memories(created_at DESC);
CREATE INDEX idx_memories_updated_at ON memories(updated_at DESC);

-- Full-text search index
CREATE INDEX idx_memories_search_vector ON memories USING GIN(search_vector);

-- Text similarity indexes using trigrams
CREATE INDEX idx_memories_heading_trgm ON memories USING GIN(heading gin_trgm_ops);
CREATE INDEX idx_memories_summary_trgm ON memories USING GIN(summary gin_trgm_ops);

-- Content filtering indexes
CREATE INDEX idx_memories_source ON memories(source);
CREATE INDEX idx_memories_importance ON memories(importance_score DESC);

-- Tag-related indexes
CREATE INDEX idx_memory_tags_tag ON memory_tags(tag);
CREATE INDEX idx_memory_tags_memory_id ON memory_tags(memory_id);
CREATE INDEX idx_memory_tags_composite ON memory_tags(memory_id, tag);

-- Metadata indexes
CREATE INDEX idx_memory_metadata_key ON memory_metadata(key);
CREATE INDEX idx_memory_metadata_memory_id ON memory_metadata(memory_id);
CREATE INDEX idx_memory_metadata_value ON memory_metadata USING GIN(value);

SELECT 'Indexes created successfully' AS status;

-- ============================================================================
-- TRIGGERS AND FUNCTIONS
-- ============================================================================

-- Function to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to call the update function
CREATE TRIGGER update_memories_updated_at 
    BEFORE UPDATE ON memories 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

SELECT 'Triggers created successfully' AS status;

-- ============================================================================
-- SEMANTIC SEARCH FUNCTION
-- ============================================================================

-- Advanced semantic search function with multiple filter options
CREATE OR REPLACE FUNCTION search_memories_semantic(
    query_embedding VECTOR(1536),
    similarity_threshold FLOAT DEFAULT 0.1,
    limit_count INTEGER DEFAULT 10,
    min_importance FLOAT DEFAULT 0.0,
    source_filter TEXT DEFAULT NULL,
    tag_filter TEXT DEFAULT NULL,
    date_from TIMESTAMPTZ DEFAULT NULL,
    date_to TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(
    memory_id UUID,
    heading TEXT,
    summary TEXT,
    context TEXT,
    similarity FLOAT,
    importance_score FLOAT,
    created_at TIMESTAMPTZ,
    tags TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.id,
        m.heading,
        m.summary,
        m.context,
        1 - (m.embedding <=> query_embedding) AS similarity,
        m.importance_score,
        m.created_at,
        COALESCE(
            ARRAY_AGG(mt.tag ORDER BY mt.tag) FILTER (WHERE mt.tag IS NOT NULL),
            ARRAY[]::TEXT[]
        ) AS tags
    FROM memories m
    LEFT JOIN memory_tags mt ON m.id = mt.memory_id
    WHERE 
        (1 - (m.embedding <=> query_embedding)) >= similarity_threshold
        AND m.importance_score >= min_importance
        AND (source_filter IS NULL OR m.source = source_filter)
        AND (date_from IS NULL OR m.created_at >= date_from)
        AND (date_to IS NULL OR m.created_at <= date_to)
        AND (tag_filter IS NULL OR m.id IN (
            SELECT memory_id FROM memory_tags WHERE tag = tag_filter
        ))
    GROUP BY m.id, m.heading, m.summary, m.context, m.embedding, m.importance_score, m.created_at
    ORDER BY similarity DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Text-based search function using full-text search
CREATE OR REPLACE FUNCTION search_memories_text(
    search_query TEXT,
    limit_count INTEGER DEFAULT 10
)
RETURNS TABLE(
    memory_id UUID,
    heading TEXT,
    summary TEXT,
    context TEXT,
    rank FLOAT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.id,
        m.heading,
        m.summary,
        m.context,
        ts_rank(m.search_vector, plainto_tsquery('english', search_query)) AS rank,
        m.created_at
    FROM memories m
    WHERE m.search_vector @@ plainto_tsquery('english', search_query)
    ORDER BY rank DESC, m.created_at DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

SELECT 'Search functions created successfully' AS status;

-- ============================================================================
-- UTILITY VIEWS
-- ============================================================================

-- Statistics view for monitoring
CREATE VIEW memory_stats AS
SELECT 
    COUNT(*) as total_memories,
    COUNT(*) FILTER (WHERE m.created_at >= CURRENT_DATE - INTERVAL '7 days') as recent_memories,
    COUNT(*) FILTER (WHERE m.created_at >= CURRENT_DATE - INTERVAL '30 days') as monthly_memories,
    AVG(m.importance_score) as avg_importance,
    COUNT(DISTINCT m.source) as unique_sources,
    COUNT(DISTINCT mt.tag) as unique_tags
FROM memories m
LEFT JOIN memory_tags mt ON m.id = mt.memory_id;

-- Comprehensive view with all related data
CREATE VIEW memories_with_tags AS
SELECT 
    m.id,
    m.heading,
    m.summary,
    m.context,
    m.source,
    m.importance_score,
    m.created_at,
    m.updated_at,
    COALESCE(
        ARRAY_AGG(mt.tag ORDER BY mt.tag) FILTER (WHERE mt.tag IS NOT NULL),
        ARRAY[]::TEXT[]
    ) AS tags
FROM memories m
LEFT JOIN memory_tags mt ON m.id = mt.memory_id
GROUP BY m.id, m.heading, m.summary, m.context, m.source, m.importance_score, m.created_at, m.updated_at;

SELECT 'Views created successfully' AS status;

-- ============================================================================
-- DATABASE OPTIMIZATION SETTINGS
-- ============================================================================

-- Optimize PostgreSQL settings for vector operations
-- Note: These settings optimize performance for the SyntaxRAG workload
ALTER SYSTEM SET shared_preload_libraries = 'vector';
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
ALTER SYSTEM SET random_page_cost = 1.1;  -- Optimized for SSD storage

-- Configuration will take effect after PostgreSQL restart
SELECT 'Performance settings configured (restart required)' AS status;

-- ============================================================================
-- SAMPLE DATA (Optional - for testing)
-- ============================================================================

-- Uncomment the following section to insert sample data for testing

/*
-- Insert sample memories with realistic embeddings (zero vectors for demo)
INSERT INTO memories (heading, summary, context, source, importance_score, embedding) VALUES
(
    'Python Virtual Environment Setup',
    'Discussion about creating Python virtual environments using venv command, activating them on different operating systems, and managing project dependencies with pip freeze and requirements.txt files.',
    'Python development best practices and environment management',
    'chat',
    0.8,
    ARRAY[0.0]::float[] || ARRAY(SELECT 0.0 FROM generate_series(1, 1535))
),
(
    'PostgreSQL Connection Management',
    'Technical guide on connecting to PostgreSQL databases using psycopg2 library, including connection string configuration and implementing connection pooling for production applications.',
    'Database connectivity and performance optimization',
    'documentation',
    0.7,
    ARRAY[0.0]::float[] || ARRAY(SELECT 0.0 FROM generate_series(1, 1535))
),
(
    'Vector Search with pgvector',
    'Implementation details for vector similarity search using PostgreSQL pgvector extension, including index creation with HNSW algorithm and cosine distance calculations.',
    'Vector database and semantic search implementation',
    'technical_discussion',
    0.9,
    ARRAY[0.0]::float[] || ARRAY(SELECT 0.0 FROM generate_series(1, 1535))
);

-- Add corresponding tags
INSERT INTO memory_tags (memory_id, tag) 
SELECT id, unnest(ARRAY['python', 'development', 'virtual-environment', 'pip', 'dependencies'])
FROM memories WHERE heading = 'Python Virtual Environment Setup';

INSERT INTO memory_tags (memory_id, tag) 
SELECT id, unnest(ARRAY['postgresql', 'database', 'python', 'psycopg2', 'connection-pooling'])
FROM memories WHERE heading = 'PostgreSQL Connection Management';

INSERT INTO memory_tags (memory_id, tag) 
SELECT id, unnest(ARRAY['vector-search', 'pgvector', 'similarity', 'embeddings', 'hnsw'])
FROM memories WHERE heading = 'Vector Search with pgvector';

SELECT 'Sample data inserted' AS status;
*/

-- ============================================================================
-- VERIFICATION AND STATUS
-- ============================================================================

-- Verify the setup
SELECT 'Database setup verification:' AS status;

-- Check extensions
SELECT 'Installed extensions:' AS info;
SELECT extname, extversion FROM pg_extension 
WHERE extname IN ('vector', 'uuid-ossp', 'pg_trgm', 'btree_gist')
ORDER BY extname;

-- Check tables
SELECT 'Created tables:' AS info;
SELECT schemaname, tablename, hasindexes, hastriggers
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- Check functions
SELECT 'Created functions:' AS info;
SELECT proname, pronargs 
FROM pg_proc 
WHERE proname IN ('search_memories_semantic', 'search_memories_text', 'update_updated_at_column')
ORDER BY proname;

-- Check views
SELECT 'Created views:' AS info;
SELECT schemaname, viewname
FROM pg_views 
WHERE schemaname = 'public'
ORDER BY viewname;

-- Show database size
SELECT 'Database size: ' || pg_size_pretty(pg_database_size(current_database())) AS info;

-- Show memory count
SELECT 'Total memories: ' || COUNT(*) FROM memories;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

SELECT '
============================================================================
🎉 SyntaxRAG Database Initialization Complete! 🎉
============================================================================

✅ Extensions: vector, uuid-ossp, pg_trgm, btree_gist
✅ Tables: memories, memory_tags, memory_metadata  
✅ Indexes: HNSW vector index, full-text search, performance indexes
✅ Functions: semantic search, text search, auto-update triggers
✅ Views: memory_stats, memories_with_tags
✅ Configuration: Optimized for vector operations

🔧 Configuration Details:
   • Database: agent_recall
   • Embedding Dimension: 1536 (text-embedding-3-small)
   • Vector Index: HNSW with cosine similarity
   • Full-text Search: English language with weighted ranking

📝 Next Steps:
   1. Restart PostgreSQL to apply performance settings
   2. Update your application configuration:
      - POSTGRES_PASSWORD=agent_recall_password
      - EMBEDDING_DIMENSION=1536  
      - EMBEDDING_MODEL=text-embedding-3-small
   3. Test the recall agent functionality

🚀 Your SyntaxRAG recall agent is ready to store and retrieve memories!
============================================================================
' AS completion_message;

-- Final status
\echo 'SyntaxRAG database initialization completed successfully!'
