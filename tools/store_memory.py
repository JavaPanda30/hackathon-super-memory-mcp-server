"""
Tool for storing memory data in PostgreSQL with pgvector.
"""
import uuid
from typing import Dict, List, Any
from core.postgres_store import PostgresStore
from utils.logger import setup_logger, log_tool_execution

logger = setup_logger(__name__)

class StoreMemoryTool:
    """Tool for storing memories in PostgreSQL with pgvector."""
    
    def __init__(self):
        """Initialize PostgreSQL storage backend."""
        self.store = PostgresStore()
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Store memory data in PostgreSQL.
        
        Args:
            input_data: Dictionary containing:
                - heading: Memory heading (required)
                - summary: Memory summary (required)
                - embedding: Text embedding (required)
        
        Returns:
            Dictionary containing:
                - memory_id: Stored memory identifier (UUID)
                - success: Boolean indicating success
                - error: Error message if failed
        """
        try:
            heading = input_data.get('heading', '')
            summary = input_data.get('summary', '')
            embedding = input_data.get('embedding', [])
            
            # Validate required fields
            if not heading:
                return {
                    "success": False,
                    "error": "heading is required"
                }
            
            if not summary:
                return {
                    "success": False,
                    "error": "summary is required"
                }
            
            if not embedding:
                return {
                    "success": False,
                    "error": "embedding is required"
                }
            
            # Store memory in PostgreSQL (simplified schema)
            stored_memory_id = self.store.store_memory(
                heading=heading,
                summary=summary,
                embedding=embedding
            )
            
            result = {
                "memory_id": stored_memory_id,
                "success": True
            }
            
            log_tool_execution("StoreMemoryTool", input_data, result)
            logger.info(f"Stored memory {stored_memory_id}")
            
            return result
            
        except Exception as e:
            error_msg = f"Failed to store memory: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }
    
    def get_storage_stats(self) -> Dict[str, Any]:
        """Get statistics about stored data."""
        return self.store.get_stats()
