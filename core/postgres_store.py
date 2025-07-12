import psycopg2
from typing import List, Dict, Any, Tuple, Optional
from datetime import datetime
from config.settings import settings
from utils.logger import setup_logger

logger = setup_logger(__name__)


class PostgresStore:
    """PostgreSQL-based storage with pgvector for embeddings."""

    def __init__(self):
        self.connection = None
        self._connect()
        self._initialize_db()

    def _connect(self):
        try:
            self.connection = psycopg2.connect(**settings.DB_CONFIG)
            logger.info("Connected to PostgreSQL")
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            raise

    def _initialize_db(self):
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("CREATE EXTENSION IF NOT EXISTS vector;")
                cursor.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")

                cursor.execute(f'''
                    CREATE TABLE IF NOT EXISTS memories (
                        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                        heading TEXT NOT NULL,
                        summary TEXT NOT NULL,
                        embedding VECTOR({settings.EMBEDDING_DIMENSION}),
                        created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                ''')

                cursor.execute(f'''
                    CREATE INDEX IF NOT EXISTS idx_embedding 
                    ON memories USING ivfflat (embedding vector_cosine_ops)
                    WITH (lists = 100);
                ''')

                cursor.execute("CREATE INDEX IF NOT EXISTS idx_created_at ON memories(created_at);")

                self.connection.commit()
                logger.info("Database initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}")
            self.connection.rollback()
            raise

    def store_memory(self, heading: str, summary: str, embedding: List[float]) -> str:
        """Insert memory into the database and return its UUID."""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute('''
                    INSERT INTO memories (heading, summary, embedding)
                    VALUES (%s, %s, %s)
                    RETURNING id
                ''', (heading, summary, embedding))
                memory_id = cursor.fetchone()[0]
                self.connection.commit()
                logger.debug(f"Stored memory {memory_id}")
                return str(memory_id)
        except Exception as e:
            logger.error(f"Failed to store memory: {e}")
            self.connection.rollback()
            raise

    def search_similar(
        self, query_embedding: List[float], limit: int = 5, similarity_threshold: float = 0.1
    ) -> List[Tuple[float, Dict[str, Any]]]:
        """Search for similar memories using vector similarity."""
        try:
            with self.connection.cursor() as cursor:
                placeholder_vector = ','.join(map(str, query_embedding))
                cursor.execute(f'''
                    SELECT id, heading, summary, created_at,
                           1 - (embedding <=> ARRAY[{placeholder_vector}]::vector) AS similarity
                    FROM memories
                    WHERE 1 - (embedding <=> ARRAY[{placeholder_vector}]::vector) >= %s
                    ORDER BY embedding <=> ARRAY[{placeholder_vector}]::vector
                    LIMIT %s
                ''', (similarity_threshold, limit))

                results = []
                for row in cursor.fetchall():
                    memory = {
                        "id": str(row[0]),
                        "heading": row[1],
                        "summary": row[2],
                        "created_at": row[3].isoformat() if row[3] else None
                    }
                    similarity = float(row[4])
                    results.append((similarity, memory))

                logger.debug(f"Found {len(results)} similar memories")
                return results
        except Exception as e:
            logger.error(f"Failed to search similar memories: {e}")
            return []

    def fetch_recent_memories(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Fetch recent memory entries by creation time."""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute('''
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
                    for row in cursor.fetchall()
                ]
        except Exception as e:
            logger.error(f"Failed to fetch recent memories: {e}")
            return []

    def get_memory_by_id(self, memory_id: str) -> Optional[Dict[str, Any]]:
        """Fetch a memory by its UUID."""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute('''
                    SELECT id, heading, summary, created_at
                    FROM memories
                    WHERE id = %s
                ''', (memory_id,))

                row = cursor.fetchone()
                if row:
                    return {
                        "id": str(row[0]),
                        "heading": row[1],
                        "summary": row[2],
                        "created_at": row[3].isoformat() if row[3] else None
                    }
                return None
        except Exception as e:
            logger.error(f"Failed to get memory by ID: {e}")
            return None

    def delete_memory(self, memory_id: str) -> bool:
        """Delete a memory by its UUID."""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("DELETE FROM memories WHERE id = %s", (memory_id,))
                deleted = cursor.rowcount > 0
                self.connection.commit()

                if deleted:
                    logger.info(f"Deleted memory {memory_id}")
                return deleted
        except Exception as e:
            logger.error(f"Failed to delete memory: {e}")
            self.connection.rollback()
            return False

    def get_stats(self) -> Dict[str, Any]:
        """Get storage statistics."""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("SELECT COUNT(*) FROM memories")
                total = cursor.fetchone()[0]

                cursor.execute('''
                    SELECT DATE(created_at) as date, COUNT(*) 
                    FROM memories 
                    WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
                    GROUP BY DATE(created_at)
                    ORDER BY date
                ''')
                recent_activity = dict(cursor.fetchall())

                return {
                    "total_memories": total,
                    "recent_activity": recent_activity,
                    "database_url": f"postgresql://{settings.POSTGRES_USER}:***@{settings.POSTGRES_HOST}:{settings.POSTGRES_PORT}/{settings.POSTGRES_DB}"
                }

        except Exception as e:
            logger.error(f"Failed to get stats: {e}")
            return {"error": str(e)}

    def close(self):
        if hasattr(self, "connection") and self.connection:
            try:
                self.connection.close()
                logger.info("Database connection closed")
            except Exception as e:
                logger.warning(f"Failed to close connection: {e}")

    def __del__(self):
        self.close()
