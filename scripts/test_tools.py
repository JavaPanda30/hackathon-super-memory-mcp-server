#!/usr/bin/env python3
"""
Test script for the simplified MCP server with 2 tools.
"""

from tools.summarize_and_store import SummarizeAndStoreTool
from tools.fetch_context import FetchContextTool

def test_summarize_and_store():
    """Test the summarize and store tool."""
    print("Testing SummarizeAndStoreTool...")
    
    tool = SummarizeAndStoreTool()
    
    # Test data
    test_input = {
        "chat_log": [
            "User: I need help setting up a Python FastAPI server",
            "Assistant: I can help you create a FastAPI server. Let me show you the basic structure.",
            "User: Great! I also need to add database integration",
            "Assistant: For database integration, I recommend using SQLAlchemy with PostgreSQL."
        ],
        "context": "Setting up web development environment",
        "tags": ["fastapi", "python", "database"],
        "metadata": {"session_id": "test-session-1"}
    }
    
    try:
        result = tool.run(test_input)
        print(f"✅ Success: {result.get('success', False)}")
        print(f"📝 Heading: {result.get('heading', 'N/A')}")
        print(f"💾 Memory ID: {result.get('memory_id', 'N/A')}")
        print(f"📄 Summary length: {len(result.get('summary', ''))}")
        return result.get('memory_id') if result.get('success') else None
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def test_fetch_context(memory_id=None):
    """Test the fetch context tool."""
    print("\nTesting FetchContextTool...")
    
    tool = FetchContextTool()
    
    # Test data
    test_input = {
        "query": "FastAPI Python server setup",
        "limit": 3,
        "similarity_threshold": 0.1
    }
    
    try:
        result = tool.run(test_input)
        print(f"✅ Success: {result.get('success', False)}")
        print(f"🔍 Query: {result.get('query', 'N/A')}")
        
        results = result.get('results', [])
        print(f"📊 Found {len(results)} results")
        
        for i, item in enumerate(results[:2]):  # Show first 2 results
            print(f"  {i+1}. Similarity: {item.get('similarity', 0):.3f}")
            print(f"     Heading: {item.get('heading', 'N/A')}")
            
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    print("🧪 Testing MCP Server Tools\n")
    
    # Test 1: Summarize and store
    memory_id = test_summarize_and_store()
    
    # Test 2: Fetch context  
    test_fetch_context(memory_id)
    
    print("\n✨ Testing completed!")
