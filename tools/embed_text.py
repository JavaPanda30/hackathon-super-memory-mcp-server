"""
Tool for generating embeddings from text using sentence-transformers.
"""
import openai
from typing import Dict, List, Any
from core.model_loader import ModelLoader
from utils.logger import setup_logger, log_tool_execution
from config.settings import settings
logger = setup_logger(__name__)

class EmbedTextTool:
    """Tool for generating text embeddings."""
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate embedding for input text.
        
        Args:
            input_data: Dictionary containing:
                - text: Text to embed (required)
                - normalize: Whether to normalize the embedding (default: True)
        
        Returns:
            Dictionary containing:
                - embedding: List of floats representing the text embedding
                - dimension: Embedding dimension
                - success: Boolean indicating success
                - error: Error message if failed
        """
        try:
            text = input_data.get('text', '')
            normalize = input_data.get('normalize', True)
            
            if not text:
                return {
                    "success": False,
                    "error": "text is required and cannot be empty"
                }
            
            # Generate embedding
            embedding = self._generate_embedding(text, normalize)
            
            result = {
                "embedding": embedding,
                "dimension": len(embedding),
                "success": True
            }
            
            log_tool_execution("EmbedTextTool", {"text_length": len(text)}, 
                             {"dimension": len(embedding), "success": True})
            return result
            
        except Exception as e:
            error_msg = f"Failed to generate embedding: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }
    
    def _generate_embedding(self, text: str, normalize: bool = True) -> List[float]:
        """Generate embedding using sentence-transformers."""
        model_name = settings.EMBEDDING_MODEL
        # Generate embedding
        response = openai.embeddings.create(
             input=[text],
             model=model_name
             ) 
        # Convert to list of floats
        embedding_list = response.data[0].embedding
        
        logger.debug(f"Generated embedding with dimension {len(embedding_list)}")
        return embedding_list
