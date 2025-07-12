from typing import Dict, List, Any
from core.model_loader import ModelLoader
from utils.logger import setup_logger, log_tool_execution

logger = setup_logger(__name__)

class SummarizeChatTool:
    """Tool for summarizing chat logs into structured summaries."""
    
    def run(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Summarize a chat log into heading and summary.
        
        Args:
            input_data: Dictionary containing:
                - chat_log: List of strings representing chat messages
                - context: Optional context about the conversation
        
        Returns:
            Dictionary containing:
                - heading: Generated heading for the conversation
                - summary: Detailed summary of meaningful changes
                - success: Boolean indicating success
                - error: Error message if failed
        """
        try:
            chat_log = input_data.get('chat_log', [])
            context = input_data.get('context', '')
            
            if not chat_log:
                return {
                    "success": False,
                    "error": "chat_log is required and cannot be empty"
                }
            
            # Generate summary using OpenAI
            heading, summary = self._generate_summary(chat_log, context)
            
            result = {
                "heading": heading,
                "summary": summary,
                "success": True
            }
            
            log_tool_execution("SummarizeChatTool", input_data, result)
            return result
            
        except Exception as e:
            error_msg = f"Failed to summarize chat: {str(e)}"
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
                temperature=0.3
            )
            
            content = response.choices[0].message.content
            
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
