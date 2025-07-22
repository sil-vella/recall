FROM python:3.9-slim

# Add build argument for cleaning pycache
ARG CLEAN_PYCACHE=false

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements file first (for better caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code (excluding unnecessary directories)
COPY app.py .
COPY __init__.py .
COPY system/ ./system/
COPY utils/ ./utils/
# COPY plugins/ ./plugins/  # REMOVED: Plugin system deprecated
COPY tools/ ./tools/

# Clean pycache if requested
RUN if [ "$CLEAN_PYCACHE" = "true" ]; then \
        find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true; \
        find . -name "*.pyc" -type f -delete 2>/dev/null || true; \
        find . -name "*.pyo" -type f -delete 2>/dev/null || true; \
        echo "🧹 Python cache cleaned during build"; \
    fi

# Set environment variables
ENV PYTHONPATH="/app:$PYTHONPATH"
ENV FLASK_HOST="0.0.0.0"
ENV FLASK_PORT="5001"

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 5001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:5001/health || exit 1

# Start Flask application with Gunicorn (production mode)
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "1", "--timeout", "120", "--keep-alive", "5", "app:app"] 