# Agent Recall - Memory System for Code Agents

A tool-driven, modular Python system for persistent memory about meaningful code changes. Designed for AI agents like GitHub Copilot to maintain context across coding sessions.

## 🧱 Architecture

This system uses a **tool-centric architecture** with PostgreSQL and pgvector for high-performance vector storage and retrieval. Each core function is implemented as a standalone tool following a consistent interface.

### Core Components

- **SummarizeChatTool**: Generates meaningful summaries from developer conversations
- **EmbedTextTool**: Creates vector embeddings using sentence-transformers
- **StoreMemoryTool**: Persists memories in PostgreSQL with pgvector
- **FetchContextTool**: Retrieves relevant memories using semantic and metadata search
- **MemoryPipelineTool**: Orchestrates the complete memory creation process
- **PromptMemoryTool**: Interactive CLI for memory management

## 🚀 Quick Start

### Prerequisites

- Python 3.8+
- PostgreSQL 12+ with pgvector extension
- OpenAI API key

### 1. Install Dependencies

```bash
# Using pip
pip install -r requirements.txt

# Or using uv (recommended)
uv sync
```

### 2. Setup PostgreSQL with pgvector

#### Option A: Using Docker (Recommended)

```bash
# Run PostgreSQL with pgvector
docker run -d \
  --name agent-recall-db \
  -e POSTGRES_PASSWORD=your_password \
  -e POSTGRES_DB=agent_recall \
  -p 5432:5432 \
  pgvector/pgvector:pg16
```

#### Option B: Local Installation

Install PostgreSQL and the pgvector extension:

```bash
# On macOS
brew install postgresql pgvector

# On Ubuntu
sudo apt install postgresql postgresql-contrib
# Install pgvector from source or package manager
```

### 3. Configuration

Copy the environment template and configure:

```bash
cp .env.example .env
```

Edit `.env` with your credentials:

```env
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here

# PostgreSQL Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=agent_recall
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_postgres_password_here
```

### 4. Initialize Database

```bash
python setup_database.py
```

### 5. Test the System

```bash
python run_memory_pipeline.py
```

## 🛠 Tool Usage

### Basic Memory Creation

```python
from tools.memory_pipeline import MemoryPipelineTool

pipeline = MemoryPipelineTool()
result = pipeline.run({
    "chat_log": [
        "User: How do I implement JWT authentication?",
        "Assistant: Here's how to create JWT tokens in Python...",
        # ... more conversation
    ],
    "metadata": {
        "project": "auth_service",
        "file_path": "auth/jwt_handler.py",
        "tags": ["authentication", "jwt", "security"]
    }
})

print(f"Memory created: {result['memory_id']}")
```

### Semantic Search

```python
from tools.fetch_context import FetchContextTool

fetch_tool = FetchContextTool()
results = fetch_tool.run({
    "query": "JWT token authentication",
    "limit": 5,
    "similarity_threshold": 0.3
})

for memory in results["memories"]:
    print(f"- {memory['heading']} (similarity: {memory['similarity_score']:.2f})")
```

### Interactive Memory Creation

```python
from tools.prompt_memory import PromptMemoryTool

prompt_tool = PromptMemoryTool()
result = prompt_tool.run({
    "chat_log": your_chat_messages,
    "auto_confirm": False  # Enables interactive editing
})
```

## 📁 Project Structure

```
agent_recall/
├── tools/                     # Core tool implementations
│   ├── summarize_chat.py     # GPT-4 powered summarization
│   ├── embed_text.py         # Sentence transformer embeddings
│   ├── store_memory.py       # PostgreSQL storage
│   ├── fetch_context.py      # Semantic + metadata search
│   ├── memory_pipeline.py    # End-to-end pipeline
│   └── prompt_memory.py      # Interactive CLI tool
│
├── core/                     # Core infrastructure
│   ├── postgres_store.py     # PostgreSQL + pgvector backend
│   └── model_loader.py       # AI model management
│
├── config/
│   └── settings.py           # Configuration management
│
├── utils/
│   └── logger.py            # Logging utilities
│
├── setup_database.py        # Database initialization
├── run_memory_pipeline.py   # CLI demonstration
└── requirements.txt         # Python dependencies
```

## 🔧 Advanced Configuration

### Custom Models

```env
# Use different OpenAI model
OPENAI_MODEL=gpt-3.5-turbo

# Use different embedding model
EMBEDDING_MODEL=all-mpnet-base-v2

# Adjust embedding dimension
EMBEDDING_DIMENSION=768
```

### Database Tuning

For production deployments, consider these PostgreSQL optimizations:

```sql
-- Increase work_mem for better vector operations
SET work_mem = '256MB';

-- Optimize for vector similarity searches
SET max_parallel_workers_per_gather = 4;
```

## 🧪 Testing

Run the included CLI tool to test functionality:

```bash
python run_memory_pipeline.py
```

This provides an interactive menu to:
- Create sample memories
- Search existing memories  
- Interactive memory creation
- View statistics

## 🔍 Search Capabilities

The system supports multiple search modes:

1. **Semantic Search**: Vector similarity using pgvector
2. **Metadata Search**: Filter by project, file, tags, dates
3. **Hybrid Search**: Combines both approaches for best results

### Search Examples

```python
# Semantic search
fetch_tool.run({
    "query": "error handling patterns",
    "search_type": "semantic"
})

# Metadata filtering
fetch_tool.run({
    "project": "web_app",
    "tags": ["authentication"],
    "search_type": "metadata"
})

# Hybrid (recommended)
fetch_tool.run({
    "query": "database connection pooling",
    "project": "backend_service",
    "search_type": "hybrid"
})
```

## 🚦 Performance

- **Vector Storage**: PostgreSQL with pgvector provides excellent performance for similarity search
- **Indexing**: Automatic IVFFlat indexing for sub-linear search time
- **Scalability**: Handles thousands of memories efficiently
- **Memory Usage**: Optimized for production deployments

## 🛡 Security

- Environment-based configuration for sensitive data
- PostgreSQL native security features
- No API endpoints exposed by default
- Tool-based architecture for secure agent integration

## 🤝 Integration

### VS Code Extension

The tools can be integrated into VS Code extensions:

```javascript
// Example VS Code extension integration
const { exec } = require('child_process');

function storeMemory(chatLog, metadata) {
    const command = `python -c "
from tools.memory_pipeline import MemoryPipelineTool
import json
result = MemoryPipelineTool().run(${JSON.stringify({chat_log: chatLog, metadata})})
print(json.dumps(result))
"`;
    
    exec(command, (error, stdout) => {
        const result = JSON.parse(stdout);
        console.log('Memory stored:', result.memory_id);
    });
}
```

### MCP Server

The existing MCP server can be extended to use these tools:

```python
from mcp.server.fastmcp import FastMCP
from tools.memory_pipeline import MemoryPipelineTool
from tools.fetch_context import FetchContextTool

mcp = FastMCP("agent-recall")

@mcp.tool()
def store_conversation(chat_log: list[str], metadata: dict = {}):
    """Store a conversation in memory."""
    pipeline = MemoryPipelineTool()
    return pipeline.run({"chat_log": chat_log, "metadata": metadata})

@mcp.tool()
def recall_context(query: str, limit: int = 5):
    """Recall relevant context from memory."""
    fetch_tool = FetchContextTool()
    return fetch_tool.run({"query": query, "limit": limit})
```

## 📊 Monitoring

Check system statistics:

```python
from tools.store_memory import StoreMemoryTool

store_tool = StoreMemoryTool()
stats = store_tool.get_storage_stats()
print(f"Total memories: {stats['total_memories']}")
print(f"Projects: {list(stats['projects'].keys())}")
```

## 🐛 Troubleshooting

### Common Issues

1. **pgvector not found**: Ensure the pgvector extension is installed
2. **Connection refused**: Check PostgreSQL is running and credentials are correct
3. **OpenAI API errors**: Verify API key and quota
4. **Memory errors**: Adjust PostgreSQL memory settings for large embeddings

### Debug Mode

Enable detailed logging:

```python
import logging
logging.getLogger("agent_recall").setLevel(logging.DEBUG)
```

## 📝 License

MIT License - see LICENSE file for details.

## 🤲 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## 📞 Support

For issues and questions:
- Check the troubleshooting section
- Review PostgreSQL and pgvector documentation
- Open an issue on GitHub
