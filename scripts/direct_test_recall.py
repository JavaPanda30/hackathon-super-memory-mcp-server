#!/usr/bin/env python3
"""
Direct test of the recall agent tools without MCP.
"""

from tools.summarize_and_store import SummarizeAndStoreTool
from tools.fetch_context import FetchContextTool

def test_recall_agent():
    """Test the recall agent functionality directly."""
    
    print("🤖 SyntaxRAG Recall Agent Demo")
    print("=" * 50)
    
    # Sample conversations to store
    sample_conversations = [
        {
            "chat_log": [
                "User: How do I set up a Python virtual environment?",
                "Assistant: You can create a Python virtual environment using 'python -m venv myenv' and activate it with 'source myenv/bin/activate' on Unix or 'myenv\\Scripts\\activate' on Windows.",
                "User: What about managing dependencies?",
                "Assistant: Use pip freeze > requirements.txt to save dependencies and pip install -r requirements.txt to install them in a new environment."
            ],
            "context": "Python development setup and virtual environments",
            "tags": ["python", "virtual-environment", "pip", "dependencies", "development-setup"]
        },
        {
            "chat_log": [
                "User: How do I connect to a PostgreSQL database in Python?",
                "Assistant: You can use psycopg2 library. Install it with 'pip install psycopg2' and connect using psycopg2.connect(host='localhost', database='mydb', user='user', password='pass').",
                "User: What about connection pooling?",
                "Assistant: For production apps, use connection pooling with psycopg2.pool or SQLAlchemy's create_engine with pool parameters."
            ],
            "context": "PostgreSQL database connectivity in Python",
            "tags": ["python", "postgresql", "psycopg2", "database", "connection-pooling", "production"]
        },
        {
            "chat_log": [
                "User: How do I implement vector search with embeddings?",
                "Assistant: You can use pgvector extension for PostgreSQL to store embeddings as vectors and perform similarity search using cosine distance.",
                "User: What's the query syntax?",
                "Assistant: Use queries like 'SELECT * FROM items ORDER BY embedding <=> query_vector LIMIT 10' where <=> is cosine distance operator.",
                "User: How do I create the vector index?",
                "Assistant: Create an index with 'CREATE INDEX ON items USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)' for better performance."
            ],
            "context": "Vector search implementation with pgvector",
            "tags": ["vector-search", "embeddings", "pgvector", "similarity", "cosine-distance", "postgresql", "indexing"]
        }
    ]
    
    # Initialize tools
    summarize_tool = SummarizeAndStoreTool()
    fetch_tool = FetchContextTool()
    
    print("\n📚 Storing sample memories...")
    memory_ids = []
    
    for i, conv in enumerate(sample_conversations, 1):
        print(f"   Storing conversation {i}...")
        try:
            result = summarize_tool.run(conv)
            if result.get("success"):
                memory_id = result.get("memory_id")
                heading = result.get("heading", "")[:60] + "..."
                print(f"   ✅ Stored: {heading}")
                print(f"      Memory ID: {memory_id}")
                memory_ids.append(memory_id)
            else:
                print(f"   ❌ Failed: {result.get('error', 'Unknown error')}")
        except Exception as e:
            print(f"   ❌ Exception: {e}")
    
    print(f"\n💾 Stored {len(memory_ids)} memories successfully!")
    
    # Now fetch relevant context with different queries
    test_queries = [
        "How to setup Python development environment with virtual environments?",
        "PostgreSQL database connection in Python",
        "Vector similarity search implementation",
        "Machine learning deployment strategies",  # This won't match much
    ]
    
    print("\n🔍 Fetching relevant context...")
    print("-" * 30)
    
    for query in test_queries:
        print(f"\n🔎 Query: '{query}'")
        
        try:
            result = fetch_tool.run({
                "query": query,
                "limit": 3,
                "similarity_threshold": 0.1
            })
            
            if result.get("success"):
                memories = result.get("memories", [])
                
                if memories:
                    print(f"   📋 Found {len(memories)} relevant memories:")
                    for memory in memories:
                        similarity = memory.get("similarity", 0)
                        heading = memory.get("heading", "No heading")
                        summary = memory.get("summary", "No summary")[:100] + "..."
                        print(f"      • {heading} (similarity: {similarity:.3f})")
                        print(f"        {summary}")
                else:
                    print("   📭 No relevant memories found")
            else:
                print(f"   ❌ Failed: {result.get('error', 'Unknown error')}")
        except Exception as e:
            print(f"   ❌ Exception: {e}")
    
    print("\n✨ Demo completed!")

if __name__ == "__main__":
    test_recall_agent()
