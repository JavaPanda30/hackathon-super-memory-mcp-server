from typing import List, Dict, Any, Tuple, Optional, cast
from datetime import datetime
from config.settings import settings
from utils.logger import setup_logger

from psycopg import connect, Connection
from pgvector.psycopg import register_vector

logger = setup_logger(__name__)

class PostgresStore:
    """PostgreSQL-based storage with pgvector for embeddings."""

    def __init__(self):
        self.connection: Connection = connect(**settings.DB_CONFIG)
        logger.info("Connected to PostgreSQL")
        register_vector(self.connection)
        self._initialize_db()

    def _initialize_db(self):
        with self.connection.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            cur.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")
            cur.execute(f'''
                        CREATE TABLE IF NOT EXISTS memories (
                    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                    heading TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    embedding VECTOR({settings.EMBEDDING_DIMENSION}),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
            ''')
            cur.execute(f'''
                CREATE INDEX IF NOT EXISTS idx_embedding 
                ON memories USING ivfflat (embedding vector_cosine_ops)
                WITH (lists = 100);
            ''')
            cur.execute("CREATE INDEX IF NOT EXISTS idx_created_at ON memories(created_at);")
            cur.execute('''
                CREATE TABLE IF NOT EXISTS memory_tags (
                    memory_id UUID REFERENCES memories(id) ON DELETE CASCADE,
                    tag TEXT NOT NULL,
                    PRIMARY KEY (memory_id, tag)
                );
            ''')
            cur.execute('''
                CREATE TABLE IF NOT EXISTS memory_metadata (
                    memory_id UUID REFERENCES memories(id) ON DELETE CASCADE,
                    key TEXT NOT NULL,
                    value TEXT,
                    PRIMARY KEY (memory_id, key)
                );
            ''')
            self.connection.commit()
            logger.info("Database initialized")

    def store_memory(self, heading: str, summary: str, embedding: List[float]) -> str:
        with self.connection.cursor() as cur:
            cur.execute(
                "INSERT INTO memories (heading, summary, embedding) VALUES (%s, %s, %s) RETURNING id",
                (heading, summary, embedding)
            )
            memory_id = cur.fetchone()[0]
            self.connection.commit()
            return str(memory_id)

    def search_similar(self, query_embedding: List[float], limit=5, similarity_threshold=0.1
    ) -> List[Tuple[float, Dict[str, Any]]]:
        placeholder = ','.join(map(str, query_embedding))
        with self.connection.cursor() as cur:
            cur.execute(f'''
                SELECT id, heading, summary, created_at,
                       1 - (embedding <=> ARRAY[{placeholder}]::vector) AS similarity
                FROM memories
                WHERE 1 - (embedding <=> ARRAY[{placeholder}]::vector) >= %s
                ORDER BY similarity DESC
                LIMIT %s
            ''', (similarity_threshold, limit))
            return [
                (
                    float(row[4]),
                    {
                        "id": str(row[0]),
                        "heading": row[1],
                        "summary": row[2],
                        "created_at": row[3].isoformat()
                    }
                )
                for row in cur.fetchall()
            ]

    def fetch_recent_memories(self, limit: int = 20) -> List[Dict[str, Any]]:
        with self.connection.cursor() as cur:
            cur.execute('''
                SELECT id, heading, summary, created_at
                FROM memories
                ORDER BY created_at DESC
                LIMIT %s
            ''', (limit,))
            return [
                {
                    "id": str(row[0]),
                    "heading": row[1],
                    "summary": row[2],
                    "created_at": row[3].isoformat() if row[3] else None
                }
                for row in cur.fetchall()
            ]

    def get_memory_by_id(self, memory_id: str) -> Optional[Dict[str, Any]]:
        with self.connection.cursor() as cur:
            cur.execute('''
                SELECT id, heading, summary, created_at
                FROM memories
                WHERE id = %s
            ''', (memory_id,))
            row = cur.fetchone()
            if row:
                return {
                    "id": str(row[0]),
                    "heading": row[1],
                    "summary": row[2],
                    "created_at": row[3].isoformat() if row[3] else None
                }
            return None

    def delete_memory(self, memory_id: str) -> bool:
        with self.connection.cursor() as cur:
            cur.execute("DELETE FROM memories WHERE id = %s", (memory_id,))
            deleted = cur.rowcount > 0
            self.connection.commit()
            return deleted

    def get_stats(self) -> Dict[str, Any]:
        with self.connection.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM memories")
            total = cur.fetchone()[0]

            cur.execute('''
                SELECT DATE(created_at), COUNT(*) 
                FROM memories 
                WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
                GROUP BY DATE(created_at)
                ORDER BY DATE(created_at)
            ''')
            recent_activity = dict(cur.fetchall())

            return {
                "total_memories": total,
                "recent_activity": recent_activity,
                "database_url": f"postgresql://{settings.POSTGRES_USER}:***@{settings.POSTGRES_HOST}:{settings.POSTGRES_PORT}/{settings.POSTGRES_DB}"
            }

    def add_tag(self, memory_id: str, tag: str):
        with self.connection.cursor() as cur:
            cur.execute('''
                INSERT INTO memory_tags (memory_id, tag)
                VALUES (%s, %s)
                ON CONFLICT (memory_id, tag) DO NOTHING
            ''', (memory_id, tag))
            self.connection.commit()

    def add_metadata(self, memory_id: str, key: str, value: Any):
        with self.connection.cursor() as cur:
            cur.execute('''
                INSERT INTO memory_metadata (memory_id, key, value)
                VALUES (%s, %s, %s)
                ON CONFLICT (memory_id, key) DO UPDATE SET value = EXCLUDED.value
            ''', (memory_id, key, value))
            self.connection.commit()

    def close(self):
        if self.connection:
            self.connection.close()
            logger.info("DB connection closed")

    def __del__(self):
        self.close()
