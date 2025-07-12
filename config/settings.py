import openai
import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    """Configuration settings for the memory system."""
    
    # OpenAI Configuration
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    client = openai.OpenAI(api_key=OPENAI_API_KEY)
    models = client.models.list()
    print([m.id for m in models.data])
    
    OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o")
    
    # Embedding Model Configuration
    EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-large")
    
    # PostgreSQL Configuration
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
    POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", "5433"))
    POSTGRES_DB = os.getenv("POSTGRES_DB", "agent_recall")
    POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "agent_recall_password")
    
    DB_CONFIG = {
        "host": POSTGRES_HOST,
        "port": POSTGRES_PORT,
        "user": POSTGRES_USER,
        "password": POSTGRES_PASSWORD,
        "database": POSTGRES_DB,
    }
    # System Configuration
    MAX_CHAT_LENGTH = int(os.getenv("MAX_CHAT_LENGTH", "50000"))
    EMBEDDING_DIMENSION = int(os.getenv("EMBEDDING_DIMENSION", "1536"))
    
    @classmethod
    def get_postgres_url(cls):
        """Get PostgreSQL connection URL."""
        return f"postgresql://{cls.POSTGRES_USER}:{cls.POSTGRES_PASSWORD}@{cls.POSTGRES_HOST}:{cls.POSTGRES_PORT}/{cls.POSTGRES_DB}"
    
    @classmethod
    def validate(cls):
        """Validate that required settings are present."""
        if not cls.OPENAI_API_KEY:
            raise ValueError("OPENAI_API_KEY environment variable is required")
        if not cls.POSTGRES_PASSWORD:
            raise ValueError("POSTGRES_PASSWORD environment variable is required")
        return True

# Create a global settings instance
settings = Settings()
