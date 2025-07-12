"""
Model loader for OpenAI and embedding models.
Handles initialization and caching of model instances.
"""
from typing import Optional
import openai
from typing import List
from config.settings import settings
from utils.logger import setup_logger

logger = setup_logger(__name__)

class ModelLoader:
    """Handles loading and caching of AI models."""
    
    _openai_client: Optional[openai.OpenAI] = None
    
    @classmethod
    def get_openai_client(cls) -> openai.OpenAI:
        """Get or create OpenAI client."""
        if cls._openai_client is None:
            settings.validate()
            cls._openai_client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)
            logger.info("OpenAI client initialized")
        return cls._openai_client
    
    @classmethod
    def get_embedding_model(cls):
        """
        Returns a function that generates embeddings using OpenAI's ada-002 model.
        """
        def embed(text: str, normalize_embeddings: bool = True) -> List[float]:
            client = cls.get_openai_client()
            response = client.embeddings.create(
               model=settings.EMBEDDING_MODEL,
               input=text
               )
            embedding = response.data[0].embedding
            # Optionally normalize
            if normalize_embeddings:
                import numpy as np
                norm = np.linalg.norm(embedding)
                if norm > 0:
                    embedding = (np.array(embedding) / norm).tolist()
            return embedding
        return embed
    
    @classmethod
    def reset(cls):
        """Reset cached models (useful for testing)."""
        cls._openai_client = None
