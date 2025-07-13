# Use a minimal Python 3.11 base image
FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/home/syntaxrag/.local/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libpq-dev \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash syntaxrag

# Set working directory and adjust permissions
WORKDIR /app
COPY . /app
RUN chown -R syntaxrag:syntaxrag /app

# Switch to non-root user
USER syntaxrag

# Copy only requirements for caching
COPY --chown=syntaxrag:syntaxrag requirements.txt pyproject.toml ./

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --user -r requirements.txt

# Expose MCP port only
EXPOSE 8000

# Run the MCP server
CMD ["python", "mcp_server.py"]
