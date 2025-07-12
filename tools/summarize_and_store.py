from typing import Dict, List, Any
from core.model_loader import ModelLoader
from core.postgres_store import PostgresStore
from utils.logger import setup_logger, log_tool_execution
import numpy as np

logger = setup_logger(__name__)

class SummarizeAndStoreTool:
    """Tool that summarizes chat logs and stores them as memories."""
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Summarize a chat log and store it as a memory.
        
        Args:
            input_data: Dictionary containing:
                - chat_log: List of strings representing chat messages
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
        try:
            chat_log = input_data.get('chat_log', [])
            context = input_data.get('context', '')
            tags = input_data.get('tags', [])
            metadata = input_data.get('metadata', {})
            
            if not chat_log:
                return {
                    "success": False,
                    "error": "chat_log is required and cannot be empty"
                }
            
            # Step 1: Generate summary using OpenAI
            heading, summary = self._generate_summary(chat_log, context)
            
            # Step 2: Generate embedding for the summary
            embedding = self._generate_embedding(summary)
            
            # Step 3: Store the memory
            memory_id = self._store_memory(heading, summary, embedding, tags, metadata)
            
            result = {
                "heading": heading,
                "summary": summary,
                "memory_id": memory_id,
                "success": True
            }
            
            log_tool_execution("SummarizeAndStoreTool", input_data, result)
            return result
            
        except Exception as e:
            error_msg = f"Failed to summarize and store chat: {str(e)}"
            logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }
    
    def _generate_summary(self, chat_log: List[str], context: str = "") -> tuple[str, str]:
        """Generate heading and summary using OpenAI."""
        client = ModelLoader.get_openai_client()
        
        # Prepare the chat log text
        chat_text = "\n".join(chat_log)
        
        # Create the prompt for summarization
        system_prompt = """You are an expert code assistant that summarizes developer conversations.
Focus on:
1. Meaningful code changes, implementations, and technical decisions
2. Problem-solving discussions and solutions
3. Architecture decisions and design patterns
4. Bug fixes and debugging insights
5. Library/framework usage and configurations

Ignore:
- Small talk and non-technical content
- Simple clarifications without code impact
- Repetitive content

Generate:
1. A concise heading (max 10 words) that captures the main technical topic
2. A detailed summary that highlights key technical insights, code changes, and decisions made

Be specific about technical details, file names, functions, and implementation approaches mentioned."""

        user_prompt = f"""Please summarize this developer conversation:

Context: {context}

Chat Log:
{chat_text}

Provide:
1. Heading: A brief title summarizing the main technical topic
2. Summary: A detailed summary of technical insights and code changes discussed"""

        try:
            response = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.3,
                timeout=120  # 2 minute timeout for long conversations
            )
            
            content = response.choices[0].message.content or ""
            
            # Parse the response to extract heading and summary
            lines = content.strip().split('\n')
            heading = ""
            summary = ""
            
            current_section = None
            summary_lines = []
            
            for line in lines:
                line = line.strip()
                if line.lower().startswith('heading:') or line.lower().startswith('1. heading:'):
                    heading = line.split(':', 1)[1].strip()
                    current_section = 'heading'
                elif line.lower().startswith('summary:') or line.lower().startswith('2. summary:'):
                    current_section = 'summary'
                elif current_section == 'summary' and line:
                    summary_lines.append(line)
                elif current_section == 'heading' and line and not heading:
                    heading = line
            
            summary = '\n'.join(summary_lines) if summary_lines else content
            
            # Fallback if parsing failed
            if not heading:
                heading = "Technical Discussion Summary"
            if not summary:
                summary = content
            
            logger.debug(f"Generated heading: {heading}")
            logger.debug(f"Generated summary length: {len(summary)} chars")
            
            return heading, summary
            
        except Exception as e:
            logger.error(f"OpenAI API error: {e}")
            # Fallback summary
            heading = "Developer Chat Summary"
            summary = f"Chat log with {len(chat_log)} messages. Failed to generate AI summary: {str(e)}"
            return heading, summary
    
    def _generate_embedding(self, text: str) -> List[float]:
        """Generate embedding for the text using OpenAI."""
        try:
            client = ModelLoader.get_openai_client()
            
            response = client.embeddings.create(
                model="text-embedding-3-small",
                input=text,
                timeout=60  # 1 minute timeout for embedding
            )
            
            embedding = response.data[0].embedding
            logger.debug(f"Generated embedding with {len(embedding)} dimensions")
            return embedding
            
        except Exception as e:
            logger.error(f"Failed to generate embedding: {e}")
            # Return a zero vector as fallback
            return [0.0] * 1536  # text-embedding-3-small dimension
    
    def _store_memory(self, heading: str, summary: str, embedding: List[float], 
                     tags: List[str], metadata: Dict[str, Any]) -> str:
        """Store the memory in PostgreSQL."""
        try:
            store = PostgresStore()
            
            # Store the memory in PostgreSQL
            memory_id = store.store_memory(
                heading=heading,
                summary=summary,
                embedding=embedding
            )
            logger.info(f"Stored memory with ID: {memory_id}")
            return memory_id
            
        except Exception as e:
            logger.error(f"Failed to store memory: {e}")
            raise
