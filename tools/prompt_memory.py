from typing import Dict, List, Any, Optional
from tools.memory_pipeline import MemoryPipelineTool
from tools.fetch_context import FetchContextTool
from utils.logger import setup_logger

logger = setup_logger(__name__)

class PromptMemoryTool:
    """Interactive tool for memory creation with user confirmation."""
    
    def __init__(self):
        """Initialize pipeline and fetch tools."""
        self.pipeline_tool = MemoryPipelineTool()
        self.fetch_tool = FetchContextTool()
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Interactive memory creation with user prompts.
        
        Args:
            input_data: Dictionary containing:
                - chat_log: List of chat messages (required)
                - context: Additional context (optional)
                - auto_confirm: Skip user prompts if True (default: False)
        
        Returns:
            Dictionary with memory creation results
        """
        try:
            chat_log = input_data.get('chat_log', [])
            context = input_data.get('context', '')
            auto_confirm = input_data.get('auto_confirm', False)
            
            if not chat_log:
                return {
                    "success": False,
                    "error": "chat_log is required"
                }
            
            # Check for similar existing memories first
            if chat_log:
                similar_memories = self._check_for_similar_memories(chat_log)
                if similar_memories and not auto_confirm:
                    print(f"\n🔍 Found {len(similar_memories)} similar memories:")
                    for i, memory in enumerate(similar_memories[:3], 1):
                        print(f"{i}. {memory.get('heading', 'No heading')}")
                        print(f"   Similarity: {memory.get('similarity_score', 0):.2f}")
                    
                    continue_creation = self._prompt_yes_no(
                        "\nDo you want to continue creating a new memory? (y/n): "
                    )
                    if not continue_creation:
                        return {
                            "success": False,
                            "error": "Memory creation cancelled by user",
                            "similar_memories": similar_memories
                        }
            
            # Generate initial summary
            print("\n🤖 Generating summary...")
            from tools.summarize_chat import SummarizeChatTool
            summarize_tool = SummarizeChatTool()
            
            summary_result = summarize_tool.run({
                "chat_log": chat_log,
                "context": context
            })
            
            if not summary_result.get("success"):
                return {
                    "success": False,
                    "error": f"Failed to generate summary: {summary_result.get('error')}"
                }
            
            heading = summary_result["heading"]
            summary = summary_result["summary"]
            
            # Show generated content to user
            print(f"\n📋 Generated Summary:")
            print(f"Heading: {heading}")
            print(f"Summary: {summary}")
            
            if not auto_confirm:
                # Ask user if they want to edit
                edit_content = self._prompt_yes_no("\nDo you want to edit the heading or summary? (y/n): ")
                
                if edit_content:
                    heading = self._prompt_input(f"Edit heading (current: {heading}): ") or heading
                    summary = self._prompt_input(f"Edit summary (current: {summary}): ") or summary
                
                # Ask for confirmation before storing
                confirm_store = self._prompt_yes_no("\nStore this memory? (y/n): ")
                if not confirm_store:
                    return {
                        "success": False,
                        "error": "Memory storage cancelled by user",
                        "generated_heading": heading,
                        "generated_summary": summary
                    }
            
            # Store the memory
            print("\n💾 Storing memory...")
            pipeline_result = self.pipeline_tool.run({
                "chat_log": [f"Heading: {heading}", f"Summary: {summary}"],
                "context": context
            })
            
            if pipeline_result.get("success"):
                print(f"✅ Memory stored successfully!")
                print(f"Memory ID: {pipeline_result.get('memory_id')}")
            
            return pipeline_result
            
        except Exception as e:
            error_msg = f"Interactive memory creation failed: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }
    
    def _check_for_similar_memories(self, chat_log: List[str]) -> List[Dict[str, Any]]:
        """Check for similar existing memories."""
        try:
            # Use first few messages as query
            query_text = " ".join(chat_log[:3])
            
            fetch_result = self.fetch_tool.run({
                "query": query_text,
                "limit": 5,
                "similarity_threshold": 0.3,
                "search_type": "semantic"
            })
            
            if fetch_result.get("success"):
                return fetch_result.get("memories", [])
            return []
            
        except Exception as e:
            logger.warning(f"Failed to check for similar memories: {e}")
            return []
    
    def _prompt_yes_no(self, message: str) -> bool:
        """Prompt user for yes/no input."""
        try:
            response = input(message).strip().lower()
            return response in ['y', 'yes', '1', 'true']
        except (EOFError, KeyboardInterrupt):
            return False
    
    def _prompt_input(self, message: str) -> Optional[str]:
        """Prompt user for text input."""
        try:
            response = input(message).strip()
            return response if response else None
        except (EOFError, KeyboardInterrupt):
            return None
    
    def list_recent_memories(self, limit: int = 10) -> Dict[str, Any]:
        """List recent memories for user review."""
        try:
            fetch_result = self.fetch_tool.run({
                "limit": limit,
                "search_type": "recent"
            })
            
            if fetch_result.get("success"):
                memories = fetch_result.get("memories", [])
                print(f"\n📚 Recent {len(memories)} memories:")
                for i, memory in enumerate(memories, 1):
                    print(f"{i}. {memory.get('heading', 'No heading')}")
                    print(f"   Created: {memory.get('created_at', 'Unknown')}")
                    print(f"   Project: {memory.get('project', 'N/A')}")
                    print()
            
            return fetch_result
            
        except Exception as e:
            error_msg = f"Failed to list memories: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }
