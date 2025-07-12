"""
Logging utility for the Agent Recall memory system.
"""
import logging
import os
from datetime import datetime

def setup_logger(name: str = "agent_recall", level: str = "INFO") -> logging.Logger:
    """
    Set up a logger with consistent formatting.
    
    Args:
        name: Logger name
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    
    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)
    
    # Only configure if not already configured
    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(getattr(logging, level.upper()))
    
    return logger

def log_tool_execution(tool_name: str, input_data: dict, output_data: dict):
    """Log tool execution for debugging purposes."""
    logger = setup_logger()
    logger.info(f"Executed {tool_name}")
    logger.debug(f"Input: {input_data}")
    logger.debug(f"Output: {output_data}")
