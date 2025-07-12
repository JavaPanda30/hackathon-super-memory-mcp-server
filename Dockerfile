# Use Python 3.11 slim image as base
FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash syntaxrag && \
    chown -R syntaxrag:syntaxrag /app
USER syntaxrag

# Copy requirements first for better caching
COPY --chown=syntaxrag:syntaxrag requirements.txt pyproject.toml ./

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Copy application code
COPY --chown=syntaxrag:syntaxrag . .

# Create necessary directories
RUN mkdir -p logs data

# Add user's pip bin to PATH
ENV PATH="/home/syntaxrag/.local/bin:$PATH"

# Expose port for MCP server
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Default command
CMD ["python", "mcp_server.py", "--host", "0.0.0.0", "--port", "8000"]
