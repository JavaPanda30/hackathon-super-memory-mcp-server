import asyncio
import uvicorn
from datetime import datetime
from fastmcp import FastMCP
from tools.summarize_and_store import SummarizeAndStoreTool
from tools.fetch_context import FetchContextTool
from fastapi import FastAPI
from datetime import datetime

# Create the MCP instance
mcp = FastMCP("syntaxrag")

# Tool 1: Summarize chat and store as memory
@mcp.tool()
def summarize_chat_and_add_to_memory(input_data: dict):
    """
    Summarize a chat log and store it as a memory in the database.
    
    Args:
        input_data: Dictionary containing:
            - chat_log: List of strings representing chat messages (required)
            - context: Optional context about the conversation
            - tags: Optional list of tags for categorization
            - metadata: Optional metadata dictionary
    
    Returns:
        Dictionary containing:
            - heading: Generated heading for the conversation
            - summary: Detailed summary of meaningful changes
            - memory_id: ID of stored memory
            - success: Boolean indicating success
            - error: Error message if failed
    """
    return SummarizeAndStoreTool().run(input_data)

# Tool 2: Fetch relevant context from stored memories
@mcp.tool()
def fetch_relevant_context_from_memories(input_data: dict):
    """
    Fetch relevant memories based on query and filters.
    
    Args:
        input_data: Dictionary containing:
            - query: Search query string (required)
            - limit: Maximum number of results (default: 5)
            - similarity_threshold: Minimum similarity score (default: 0.1)
            - date_filter: Optional date filter
    
    Returns:
        Dictionary containing:
            - results: List of matching memories with similarity scores
            - query: Original query
            - success: Boolean indicating success
            - error: Error message if failed
    """
    return FetchContextTool().run(input_data)

# Health endpoint for Docker health checks
@mcp.get("/health")
def health_check():
    """Health check endpoint for monitoring and Docker health checks."""
    try:
        # Quick database connection test
        from core.postgres_store import PostgresStore
        store = PostgresStore()
        stats = store.get_stats()
        store.close()
        
        return {
            "status": "healthy",
            "service": "SyntaxRAG MCP Server",
            "database": "connected",
            "total_memories": stats.get("total_memories", 0),
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "service": "SyntaxRAG MCP Server", 
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

if __name__ == "__main__":
    # Set environment variables for longer timeouts
    import os
    os.environ.setdefault("UVICORN_TIMEOUT_KEEP_ALIVE", "300")  # 5 minutes
    os.environ.setdefault("UVICORN_TIMEOUT_GRACEFUL_SHUTDOWN", "60")  # 1 minute
    
    mcp.run()
