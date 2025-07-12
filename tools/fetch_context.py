"""
Tool for fetching relevant context from stored memories using PostgreSQL with pgvector.
"""
from typing import Dict, List, Any, Optional, Tuple
from core.postgres_store import PostgresStore
from tools.embed_text import EmbedTextTool
from utils.logger import setup_logger, log_tool_execution

logger = setup_logger(__name__)

class FetchContextTool:
    """Tool for retrieving relevant memories using PostgreSQL with pgvector."""
    
    def __init__(self):
        """Initialize storage backend and embedding tool."""
        self.store = PostgresStore()
        self.embed_tool = EmbedTextTool()
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Fetch relevant memories based on query and filters.
        
        Args:
            input_data: Dictionary containing:
                - query: Text query for semantic search (optional)
                - limit: Maximum number of results (default: 10)
                - similarity_threshold: Minimum similarity score (default: 0.1)
                - search_type: "semantic" or "recent" (default: "semantic")
        
        Returns:
            Dictionary containing:
                - memories: List of relevant memory dictionaries
                - total_found: Number of memories found
                - search_type_used: Type of search performed
                - success: Boolean indicating success
                - error: Error message if failed
        """
        try:
            query = input_data.get('query', '')
            limit = input_data.get('limit', 10)
            similarity_threshold = input_data.get('similarity_threshold', 0.1)
            search_type = input_data.get('search_type', 'semantic')
            
            # Determine search strategy based on simplified schema
            if search_type == "semantic" and query:
                memories = self._semantic_search(query, limit, similarity_threshold)
            else:  # recent search (fallback)
                memories = self._recent_search(limit)
            
            result = {
                "memories": memories,
                "total_found": len(memories),
                "search_type_used": search_type,
                "success": True
            }
            
            log_tool_execution("FetchContextTool", input_data, 
                             {"total_found": len(memories), "search_type": search_type})
            logger.info(f"Found {len(memories)} relevant memories")
            
            return result
            
        except Exception as e:
            error_msg = f"Failed to fetch context: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }
    
    def _semantic_search(self, query: str, limit: int, 
                        similarity_threshold: float) -> List[Dict[str, Any]]:
        """Perform semantic search using pgvector similarity."""
        # Generate query embedding
        embed_result = self.embed_tool.run({"text": query})
        if not embed_result.get("success"):
            logger.warning("Failed to generate query embedding, returning empty results")
            return []
        
        query_embedding = embed_result["embedding"]
        
        # Search using pgvector
        search_results = self.store.search_similar(
            query_embedding, limit=limit, similarity_threshold=similarity_threshold
        )
        
        # Format results
        memories = []
        for similarity_score, memory_data in search_results:
            memory_data["similarity_score"] = similarity_score
            memories.append(memory_data)
        
        return memories
    
    def _recent_search(self, limit: int) -> List[Dict[str, Any]]:
        """Perform recent memories search."""
        memories = self.store.fetch_recent_memories(limit=limit)
        
        # Add similarity score of 0 for recent searches
        for memory in memories:
            memory["similarity_score"] = 0.0
        
        return memories
