import asyncio
import uvicorn
from datetime import datetime
from fastmcp import FastMCP
from tools.summarize_and_store import SummarizeAndStoreTool
from tools.fetch_context import FetchContextTool
from fastapi import FastAPI

# ✅ Fixed: Import required typing types
from typing import Any, Dict, List, Optional

# Create the MCP instance
mcp = FastMCP("syntaxrag")

@mcp.tool(
    name="send_chat_logs_and_add_to_memory",
    description="Generate a heading and summary for a chat log and store it as a memory in Postgres; returns the memory ID."
)
def send_chat_logs_and_add_to_memory(
    chat_log: List[str],
    context: Optional[str] = None,
    tags: Optional[List[str]] = None,
    metadata: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """
    Args:
        chat_log: Full chat messages to summarize.
        context: Background or context for the conversation.
        tags: Tags to categorize the memory.
        metadata: Additional metadata to store.
    Returns:
        A dict with:
            - heading (str)
            - summary (str)
            - memory_id (str)
            - success (bool)
            - error (Optional[str])
    """
    return SummarizeAndStoreTool().run({
        "chat_log": chat_log,
        "context": context,
        "tags": tags,
        "metadata": metadata
    })

@mcp.tool(
    name="fetch_relevant_context_from_memories",
    description="Query stored memories using an embedding search and return matching entries."
)
def fetch_relevant_context_from_memories(
    query: str,
    limit: int = 5,
    similarity_threshold: float = 0.1,
    date_filter: Optional[str] = None
) -> Dict[str, Any]:
    """
    Args:
        query: Input text to search with embeddings.
        limit: Max number of results.
        similarity_threshold: Minimum similarity to include.
        date_filter: ISO date to filter memories on/after.
    Returns:
        A dict with:
            - results (List[Dict[str, Any]]): similarity and memory data
            - query (str)
            - success (bool)
            - error (Optional[str])
    """
    return FetchContextTool().run({
        "query": query,
        "limit": limit,
        "similarity_threshold": similarity_threshold,
        "date_filter": date_filter
    })

if __name__ == "__main__":
    import os
    os.environ.setdefault("UVICORN_TIMEOUT_KEEP_ALIVE", "300")
    os.environ.setdefault("UVICORN_TIMEOUT_GRACEFUL_SHUTDOWN", "60")
    mcp.run(transport="stdio")
