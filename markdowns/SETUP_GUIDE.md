# SyntaxRAG MCP Server Setup Guide

## Overview
Your MCP server now has exactly 2 tools:
1. `summarize_chat_and_add_to_memory` - Summarizes chat logs and stores them as memories
2. `fetch_relevant_context_from_memories` - Fetches relevant memories based on queries

## Configuration Changes Made

### 1. MCP Server (`mcp_server.py`)
- Reduced to only 2 tools as requested
- Added timeout environment variables for longer operations
- Uses the new virtual environment Python interpreter

### 2. New Combined Tool (`tools/summarize_and_store.py`)
- Combines summarization and storage into one tool
- Handles long chat logs with proper timeouts
- Stores memories with proper embedding generation

### 3. VS Code Settings Updated
- Uses virtual environment Python: `/Users/tazamac004/SyntaxRAG/venv/bin/python`
- Added `--transport=http` argument
- Added environment variables for database and API configuration
- Added timeout configurations for long-running operations

### 4. Timeout Configurations
- OpenAI API timeout: 120 seconds for summarization, 60 seconds for embeddings
- Uvicorn keep-alive timeout: 300 seconds (5 minutes)
- Graceful shutdown timeout: 60 seconds

## Tool Usage Examples

### Tool 1: Summarize Chat and Add to Memory

**Input Format:**
```json
{
  "chat_log": [
    "User: How do I set up FastAPI?",
    "Assistant: Here's how to set up FastAPI...",
    "User: What about database integration?",
    "Assistant: For databases, use SQLAlchemy..."
  ],
  "context": "FastAPI setup discussion",
  "tags": ["fastapi", "python", "database"],
  "metadata": {
    "session_id": "chat-123",
    "user_id": "user-456"
  }
}
```

**Output:**
```json
{
  "heading": "FastAPI Setup and Database Integration",
  "summary": "Discussion about setting up FastAPI server with SQLAlchemy database integration...",
  "memory_id": "uuid-of-stored-memory",
  "success": true
}
```

### Tool 2: Fetch Relevant Context from Memories

**Input Format:**
```json
{
  "query": "How to set up FastAPI with database",
  "limit": 5,
  "similarity_threshold": 0.1,
  "date_filter": "2024-01-01"
}
```

**Output:**
```json
{
  "results": [
    {
      "id": "memory-uuid",
      "heading": "FastAPI Setup and Database Integration",
      "summary": "Discussion about...",
      "similarity": 0.85,
      "created_at": "2024-07-12T16:30:00Z"
    }
  ],
  "query": "How to set up FastAPI with database",
  "success": true
}
```

## Testing the Setup

1. **Start Docker Services:**
   ```bash
   cd /Users/tazamac004/SyntaxRAG
   docker-compose up -d
   ```

2. **Test Tool Import:**
   ```bash
   /Users/tazamac004/SyntaxRAG/venv/bin/python test_tools.py
   ```

3. **Test MCP Server:**
   ```bash
   /Users/tazamac004/SyntaxRAG/venv/bin/python mcp_server.py --transport=http
   ```

4. **Test in VS Code:**
   - Open VS Code
   - Use MCP Inspector or GitHub Copilot Chat
   - The `syntaxRag` server should appear with 2 tools

## Environment Setup

Make sure your `.env` file contains:
```env
OPENAI_API_KEY=your_actual_api_key
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=syntaxrag
POSTGRES_USER=syntaxrag
POSTGRES_PASSWORD=syntaxrag123
EMBEDDING_DIMENSION=1536
```

## Troubleshooting

### Common Issues:
1. **Database Connection Error:** Ensure Docker PostgreSQL is running
2. **OpenAI API Error:** Check your API key in `.env`
3. **Timeout Error:** Long conversations may take time - the server is configured for 5-minute timeouts
4. **Import Error:** Ensure all dependencies are installed in the venv

### Logs:
Check logs for debugging:
- MCP server logs appear in VS Code Output panel
- Tool execution logs include input/output for debugging

## Next Steps

1. Test both tools with real data
2. Adjust similarity thresholds based on your needs
3. Add more metadata fields if needed
4. Monitor performance with long chat logs

Your MCP server is now optimized for exactly the 2 tools you requested with proper timeout handling for long operations!
