-- ============================================================================
-- SyntaxRAG Database Initialization Script
-- ============================================================================
-- This script sets up the complete database schema for the SyntaxRAG recall agent
-- with all necessary extensions, tables, indexes, and initial configuration.
--
-- Usage:
--   psql -h localhost -p 5433 -U postgres -d agent_recall -f init_db.sql
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For text search improvements
CREATE EXTENSION IF NOT EXISTS btree_gist; -- For advanced indexing

-- Set timezone for consistent timestamps
SET timezone = 'UTC';

-- ============================================================================
-- MAIN TABLES
-- ============================================================================

-- Drop existing tables if they exist (for clean reinstall)
DROP TABLE IF EXISTS memories CASCADE;
DROP TABLE IF EXISTS memory_tags CASCADE;
DROP TABLE IF EXISTS memory_metadata CASCADE;

-- Main memories table with vector embeddings
CREATE TABLE memories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    heading TEXT NOT NULL,
    summary TEXT NOT NULL,
    embedding VECTOR(1536), -- text-embedding-3-small dimension
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Optional metadata fields
    context TEXT,
    source TEXT DEFAULT 'chat',
    importance_score FLOAT DEFAULT 0.5 CHECK (importance_score >= 0 AND importance_score <= 1),
    
    -- Full text search
    search_vector TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english', COALESCE(heading, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(summary, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(context, '')), 'C')
    ) STORED
);

-- Tags table for memory categorization
CREATE TABLE memory_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(memory_id, tag)
);

-- Metadata table for flexible key-value storage
CREATE TABLE memory_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    memory_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(memory_id, key)
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Vector similarity search index (using HNSW for better performance with higher dimensions)
CREATE INDEX IF NOT EXISTS idx_memories_embedding_hnsw 
ON memories USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Alternative IVFFlat index (use one or the other, not both)
-- CREATE INDEX IF NOT EXISTS idx_memories_embedding_ivfflat 
-- ON memories USING ivfflat (embedding vector_cosine_ops)
-- WITH (lists = 100);

-- Time-based indexes
CREATE INDEX IF NOT EXISTS idx_memories_created_at ON memories(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_memories_updated_at ON memories(updated_at DESC);

-- Full-text search index
CREATE INDEX IF NOT EXISTS idx_memories_search_vector ON memories USING GIN(search_vector);

-- Text search indexes
CREATE INDEX IF NOT EXISTS idx_memories_heading_trgm ON memories USING GIN(heading gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_memories_summary_trgm ON memories USING GIN(summary gin_trgm_ops);

-- Importance and source indexes
CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance_score DESC);
CREATE INDEX IF NOT EXISTS idx_memories_source ON memories(source);

-- Tag indexes
CREATE INDEX IF NOT EXISTS idx_memory_tags_tag ON memory_tags(tag);
CREATE INDEX IF NOT EXISTS idx_memory_tags_memory_id ON memory_tags(memory_id);
CREATE INDEX IF NOT EXISTS idx_memory_tags_composite ON memory_tags(memory_id, tag);

-- Metadata indexes
CREATE INDEX IF NOT EXISTS idx_memory_metadata_key ON memory_metadata(key);
CREATE INDEX IF NOT EXISTS idx_memory_metadata_memory_id ON memory_metadata(memory_id);
CREATE INDEX IF NOT EXISTS idx_memory_metadata_value ON memory_metadata USING GIN(value);

-- ============================================================================
-- TRIGGERS AND FUNCTIONS
-- ============================================================================

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to automatically update updated_at
CREATE TRIGGER update_memories_updated_at 
    BEFORE UPDATE ON memories 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Function for semantic search with multiple criteria
CREATE OR REPLACE FUNCTION search_memories(
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

-- Function for text-based search
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

-- ============================================================================
-- UTILITY VIEWS
-- ============================================================================

-- View for memory statistics
CREATE OR REPLACE VIEW memory_stats AS
SELECT 
    COUNT(*) as total_memories,
    COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE - INTERVAL '7 days') as recent_memories,
    COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE - INTERVAL '30 days') as monthly_memories,
    AVG(importance_score) as avg_importance,
    COUNT(DISTINCT source) as unique_sources,
    COUNT(DISTINCT mt.tag) as unique_tags
FROM memories m
LEFT JOIN memory_tags mt ON m.id = mt.memory_id;

-- View for memories with tags
CREATE OR REPLACE VIEW memories_with_tags AS
SELECT 
    m.*,
    COALESCE(
        ARRAY_AGG(mt.tag ORDER BY mt.tag) FILTER (WHERE mt.tag IS NOT NULL),
        ARRAY[]::TEXT[]
    ) AS tags
FROM memories m
LEFT JOIN memory_tags mt ON m.id = mt.memory_id
GROUP BY m.id, m.heading, m.summary, m.embedding, m.created_at, m.updated_at, 
         m.context, m.source, m.importance_score, m.search_vector;

-- ============================================================================
-- SAMPLE DATA (Optional - uncomment to insert test data)
-- ============================================================================

/*
-- Insert sample memories for testing
INSERT INTO memories (heading, summary, context, source, importance_score) VALUES
(
    'Python Virtual Environment Setup',
    'Discussion about setting up Python virtual environments using venv, activating them, and managing dependencies with pip freeze and requirements.txt files.',
    'Python development best practices',
    'chat',
    0.8
),
(
    'PostgreSQL Connection with psycopg2',
    'Tutorial on connecting to PostgreSQL databases using psycopg2 library, including connection pooling strategies for production applications.',
    'Database connectivity patterns',
    'documentation',
    0.7
),
(
    'Vector Search Implementation',
    'Technical discussion on implementing vector similarity search using pgvector extension with cosine distance operators and IVFFlat indexing.',
    'Vector database optimization',
    'technical_discussion',
    0.9
);

-- Add sample tags
INSERT INTO memory_tags (memory_id, tag) 
SELECT id, unnest(ARRAY['python', 'development', 'virtual-environment', 'pip'])
FROM memories WHERE heading = 'Python Virtual Environment Setup';

INSERT INTO memory_tags (memory_id, tag) 
SELECT id, unnest(ARRAY['postgresql', 'database', 'python', 'psycopg2', 'connection-pooling'])
FROM memories WHERE heading = 'PostgreSQL Connection with psycopg2';

INSERT INTO memory_tags (memory_id, tag) 
SELECT id, unnest(ARRAY['vector-search', 'pgvector', 'similarity', 'embeddings', 'indexing'])
FROM memories WHERE heading = 'Vector Search Implementation';

-- Add sample metadata
INSERT INTO memory_metadata (memory_id, key, value)
SELECT id, 'difficulty_level', '"intermediate"'::jsonb
FROM memories WHERE heading = 'Python Virtual Environment Setup';

INSERT INTO memory_metadata (memory_id, key, value)
SELECT id, 'programming_language', '"python"'::jsonb
FROM memories WHERE heading LIKE '%Python%' OR heading LIKE '%psycopg2%';
*/

-- ============================================================================
-- DATABASE CONFIGURATION
-- ============================================================================

-- Optimize for vector operations
ALTER SYSTEM SET shared_preload_libraries = 'vector';
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';

-- Enable query optimization for vector operations
SET enable_seqscan = off; -- Force index usage for vector queries when possible

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'SyntaxRAG Database Initialization Complete!';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'Database: agent_recall';
    RAISE NOTICE 'Extensions: vector, uuid-ossp, pg_trgm, btree_gist';
    RAISE NOTICE 'Tables: memories, memory_tags, memory_metadata';
    RAISE NOTICE 'Indexes: Vector (HNSW), Full-text, Time-based, Tag-based';
    RAISE NOTICE 'Functions: search_memories, search_memories_text, update_updated_at_column';
    RAISE NOTICE 'Views: memory_stats, memories_with_tags';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Configure your application to use embedding dimension 1536';
    RAISE NOTICE '2. Update POSTGRES_PASSWORD in your .env file to match database';
    RAISE NOTICE '3. Run the SyntaxRAG MCP server to start using the recall agent';
    RAISE NOTICE '============================================================================';
END $$;

-- Show current database status
SELECT 
    schemaname,
    tablename,
    tableowner,
    hasindexes,
    hasrules,
    hastriggers
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- Show installed extensions
SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector', 'uuid-ossp', 'pg_trgm', 'btree_gist');

-- Show database size
SELECT pg_size_pretty(pg_database_size(current_database())) as database_size;
