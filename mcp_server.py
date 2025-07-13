from fastmcp import FastMCP
import os

# Set default environment settings for server behavior
os.environ.setdefault("UVICORN_TIMEOUT_KEEP_ALIVE", "300")
os.environ.setdefault("UVICORN_TIMEOUT_GRACEFUL_SHUTDOWN", "60")

# Initialize FastMCP instance
mcp = FastMCP("syntaxrag")

# — Prompts to trigger tools —

@mcp.prompt(name="run_summarize")
def run_summarize_prompt() -> str:
    return (
        "Call the tool 'summarize_chat_and_add_to_memory' "
        "with input_data={'chat_log': <CHAT_LOG>, 'context': '', 'tags': [], 'metadata': {}}."
    )

@mcp.prompt(name="run_context")
def run_context_prompt() -> str:
    return (
        "Call the tool 'fetch_relevant_context_from_memories' with:\n"
        "- input_data.query: a description of what you're searching for\n"
        "- input_data.filters.keywords: a list of specific keywords\n"
        "- input_data.limit: optional, defaults to 5\n\n"
        "**Example call:**\n"
        "{\n"
        "  \"tool\": \"fetch_relevant_context_from_memories\",\n"
        "  \"input_data\": {\n"
        "    \"query\": \"Find discussions about latency issues\",\n"
        "    \"filters\": {\"keywords\": [\"latency\", \"performance\"]},\n"
        "    \"limit\": 3\n"
        "  }\n"
        "}"
    )

@mcp.prompt(
    name="run_pr_analysis",
    description="Prompt to initiate GitHub PR analysis using the dedicated tool"
)
def run_pr_analysis_prompt() -> str:
    return """\
You are about to analyze a set of GitHub pull requests.

Please call the **github mcp tools** by providing:
- `pr_numbers`: a list of PR IDs to analyze (e.g. [123, 456, 789]).

The tool will fetch each PRs details—for example, the title, author, status, diff stats, and review comments—then return a summarized analysis comparing patterns, major changes, review feedback, and intents.

**Instruction:**  
Call the tool exactly like this:
```json
{
  "tool": <relevant tool from github mcp tools>,
  "input_data": {
    "pr_numbers": <PR_NUMBERS_LIST>
  }
}
```"""

# — Tools to be invoked by the prompts —

@mcp.tool()
def summarize_chat_and_add_to_memory(input_data: dict):
    """This tool takes a raw chat log or conversation text and generates a summary.

It is primarily used to:
- Condense long multi-turn chats into brief bullet points or a paragraph.
- Add metadata, tags, and contextual information.
- Store the summary and metadata into memory for later retrieval by context-aware agents or workflows.

**Input Fields:**
- `chat_log` (str, required): The full text of the conversation to summarize.
- `context` (str, optional): Optional description of where or why this chat occurred (e.g., "sprint planning").
- `tags` (list[str], optional): Keywords for categorizing the memory.
- `metadata` (dict, optional): Any additional metadata such as user, timestamp, etc.
"""
    try:
        from tools.summarize_and_store import SummarizeAndStoreTool
        return SummarizeAndStoreTool().run(input_data)
    except Exception as e:
        return {"error": f"Failed to run summarize tool: {str(e)}"}

@mcp.tool()
def fetch_relevant_context_from_memories(input_data: dict):
    """This tool searches a memory store (such as chat summaries, meeting notes, or system logs)
to retrieve entries relevant to a given query, based on specific keyword filters.

### Use Cases:
- Retrieve past conversations related to a technical issue (e.g., "database latency").
- Surface related discussions before responding to a question or prompt.
- Provide agents with historical context to enhance answers or decisions.

### Input Format:
- `query` (str, required): A free-text string that describes the topic or intent you're searching for. Used for semantic/contextual matching.
- `filters.keywords` (list[str], required): Keywords that must appear in the memory summary or tags for a match to be considered. These are exact substring filters (not embeddings).
- `limit` (int, optional): Max number of matching memory entries to return. Default is 5.
"""
    try:
        from tools.fetch_context import FetchContextTool
        return FetchContextTool().run(input_data)
    except Exception as e:
        return {"error": f"Failed to fetch context: {str(e)}"}


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)