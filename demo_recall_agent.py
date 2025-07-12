#!/usr/bin/env python3
"""
Demo script to show how to use the SyntaxRAG recall agent.
This demonstrates storing memories and fetching relevant context.
"""

import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    """Demo the recall agent functionality."""
    
    # Sample chat logs to store as memories
    sample_conversations = [
        {
            "chat_log": [
                "User: How do I set up a Python virtual environment?",
                "Assistant: You can create a Python virtual environment using 'python -m venv myenv' and activate it with 'source myenv/bin/activate' on Unix or 'myenv\\Scripts\\activate' on Windows.",
                "User: What about managing dependencies?",
                "Assistant: Use pip freeze > requirements.txt to save dependencies and pip install -r requirements.txt to install them in a new environment."
            ],
            "context": "Python development setup",
            "tags": ["python", "virtual-environment", "pip", "dependencies"]
        },
        {
            "chat_log": [
                "User: How do I connect to a PostgreSQL database in Python?",
                "Assistant: You can use psycopg2 library. Install it with 'pip install psycopg2' and connect using psycopg2.connect(host='localhost', database='mydb', user='user', password='pass').",
                "User: What about connection pooling?",
                "Assistant: For production apps, use connection pooling with psycopg2.pool or SQLAlchemy's create_engine with pool parameters."
            ],
            "context": "Database connectivity",
            "tags": ["python", "postgresql", "psycopg2", "database", "connection-pooling"]
        },
        {
            "chat_log": [
                "User: How do I implement vector search with embeddings?",
                "Assistant: You can use pgvector extension for PostgreSQL to store embeddings as vectors and perform similarity search using cosine distance.",
                "User: What's the query syntax?",
                "Assistant: Use queries like 'SELECT * FROM items ORDER BY embedding <=> query_vector LIMIT 10' where <=> is cosine distance operator."
            ],
            "context": "Vector search and embeddings",
            "tags": ["vector-search", "embeddings", "pgvector", "similarity", "cosine-distance"]
        }
    ]
    
    # Start the MCP server
    server_params = StdioServerParameters(
        command="python",
        args=["mcp_server.py"],
        env=None
    )
    
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            # Initialize the session
            await session.initialize()
            
            print("🤖 SyntaxRAG Recall Agent Demo")
            print("=" * 50)
            
            # Store sample memories
            print("\n📚 Storing sample memories...")
            memory_ids = []
            
            for i, conv in enumerate(sample_conversations, 1):
                print(f"   Storing conversation {i}...")
                result = await session.call_tool(
                    "mcp_syntaxrag_summarize_chat_and_add_to_memory",
                    {"input_data": conv}
                )
                
                if result.content and len(result.content) > 0:
                    response = result.content[0].text
                    print(f"   ✅ Stored: {response}")
                    memory_ids.append(response)
                else:
                    print(f"   ❌ Failed to store conversation {i}")
            
            print(f"\n💾 Stored {len(memory_ids)} memories successfully!")
            
            # Now fetch relevant context with different queries
            test_queries = [
                "How to setup Python development environment?",
                "PostgreSQL database connection in Python",
                "Vector similarity search implementation",
                "Machine learning deployment strategies",  # This won't match much
            ]
            
            print("\n🔍 Fetching relevant context...")
            print("-" * 30)
            
            for query in test_queries:
                print(f"\n🔎 Query: '{query}'")
                
                result = await session.call_tool(
                    "mcp_syntaxrag_fetch_relevant_context_from_memories",
                    {
                        "input_data": {
                            "query": query,
                            "limit": 3,
                            "similarity_threshold": 0.1
                        }
                    }
                )
                
                if result.content and len(result.content) > 0:
                    response = eval(result.content[0].text)  # Parse the response
                    memories = response.get("memories", [])
                    
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
                    print("   ❌ Failed to fetch memories")
            
            print("\n✨ Demo completed!")


if __name__ == "__main__":
    asyncio.run(main())
