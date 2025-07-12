"""
Tool for orchestrating the complete memory creation pipeline.
Runs: Summarize → Embed → Store in a single operation.
"""
from typing import Dict, List, Any
from tools.summarize_chat import SummarizeChatTool
from tools.embed_text import EmbedTextTool
from tools.store_memory import StoreMemoryTool
from utils.logger import setup_logger, log_tool_execution

logger = setup_logger(__name__)

class MemoryPipelineTool:
    """Tool for running the complete memory creation pipeline."""
    
    def __init__(self):
        """Initialize pipeline tools."""
        self.summarize_tool = SummarizeChatTool()
        self.embed_tool = EmbedTextTool()
        self.store_tool = StoreMemoryTool()
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Run the complete memory creation pipeline.
        
        Args:
            input_data: Dictionary containing:
                - chat_log: List of chat messages (required)
                - metadata: Additional metadata (optional)
                - context: Additional context for summarization (optional)
                - memory_id: Custom memory ID (optional)
        
        Returns:
            Dictionary containing:
                - memory_id: Created memory identifier
                - heading: Generated heading
                - summary: Generated summary
                - embedding_dimension: Dimension of the embedding
                - success: Boolean indicating success
                - error: Error message if failed
                - pipeline_steps: Status of each pipeline step
        """
        pipeline_steps = {
            "summarize": {"completed": False, "error": None},
            "embed": {"completed": False, "error": None},
            "store": {"completed": False, "error": None}
        }
        
        try:
            chat_log = input_data.get('chat_log', [])
            metadata = input_data.get('metadata', {})
            context = input_data.get('context', '')
            memory_id = input_data.get('memory_id')
            
            if not chat_log:
                return {
                    "success": False,
                    "error": "chat_log is required and cannot be empty",
                    "pipeline_steps": pipeline_steps
                }
            
            # Step 1: Summarize chat log
            logger.info("Starting memory pipeline: Step 1 - Summarizing chat")
            summarize_result = self.summarize_tool.run({
                "chat_log": chat_log,
                "context": context
            })
            
            if not summarize_result.get("success"):
                pipeline_steps["summarize"]["error"] = summarize_result.get("error")
                return {
                    "success": False,
                    "error": f"Summarization failed: {summarize_result.get('error')}",
                    "pipeline_steps": pipeline_steps
                }
            
            pipeline_steps["summarize"]["completed"] = True
            heading = summarize_result["heading"]
            summary = summarize_result["summary"]
            
            # Step 2: Generate embedding
            logger.info("Memory pipeline: Step 2 - Generating embedding")
            # Combine heading and summary for embedding
            text_to_embed = f"{heading}\n\n{summary}"
            
            embed_result = self.embed_tool.run({
                "text": text_to_embed,
                "normalize": True
            })
            
            if not embed_result.get("success"):
                pipeline_steps["embed"]["error"] = embed_result.get("error")
                return {
                    "success": False,
                    "error": f"Embedding generation failed: {embed_result.get('error')}",
                    "pipeline_steps": pipeline_steps
                }
            
            pipeline_steps["embed"]["completed"] = True
            embedding = embed_result["embedding"]
            embedding_dimension = embed_result["dimension"]
            
            # Step 3: Store memory
            logger.info("Memory pipeline: Step 3 - Storing memory")
            store_input = {
                "heading": heading,
                "summary": summary,
                "embedding": embedding
            }
            
            store_result = self.store_tool.run(store_input)
            
            if not store_result.get("success"):
                pipeline_steps["store"]["error"] = store_result.get("error")
                return {
                    "success": False,
                    "error": f"Storage failed: {store_result.get('error')}",
                    "pipeline_steps": pipeline_steps
                }
            
            pipeline_steps["store"]["completed"] = True
            stored_memory_id = store_result["memory_id"]
            
            # Success result
            result = {
                "memory_id": stored_memory_id,
                "heading": heading,
                "summary": summary,
                "embedding_dimension": embedding_dimension,
                "success": True,
                "pipeline_steps": pipeline_steps
            }
            
            log_tool_execution("MemoryPipelineTool", input_data, result)
            logger.info(f"Memory pipeline completed successfully: {stored_memory_id}")
            
            return result
            
        except Exception as e:
            error_msg = f"Memory pipeline failed: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg,
                "pipeline_steps": pipeline_steps
            }
    
    def get_pipeline_status(self) -> Dict[str, Any]:
        """Get status information about the pipeline components."""
        try:
            storage_stats = self.store_tool.get_storage_stats()
            return {
                "status": "ready",
                "components": {
                    "summarize_tool": "ready",
                    "embed_tool": "ready",
                    "store_tool": "ready"
                },
                "storage_stats": storage_stats
            }
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }
