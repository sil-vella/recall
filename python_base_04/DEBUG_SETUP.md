# Python Flask App Debug Setup

This document explains how to use the debugpy setup for debugging the Python Flask application in VS Code.

## Overview

The application now supports both production mode (with gunicorn) and debug mode (with debugpy) using the same Dockerfile and docker-compose setup.

## How to Enable Debug Mode

### Option 1: Using docker-compose (Recommended)

1. **Edit docker-compose.yml** and change the `DEBUG_MODE` environment variable:
   ```yaml
   environment:
     - DEBUG_MODE=true  # Change from 'false' to 'true'
   ```

2. **Rebuild and restart the container**:
   ```bash
   docker-compose down
   docker-compose up --build flask-external
   ```

3. **Use VS Code debug configuration**: "Python Flask App (Debug Mode)"

### Option 2: Using VS Code Launch Configuration

1. **Use the "Python Flask App (Debug Mode - Start Container)"** configuration in VS Code
2. This will start the app locally with debug mode enabled

## Debug Configurations in VS Code

### 1. "Python Flask App (Debug Mode)"
- **Purpose**: Attach to a running container in debug mode
- **Use when**: Container is already running with `DEBUG_MODE=true`
- **Connection**: localhost:5678

### 2. "Python Flask App (Debug Mode - Start Container)"
- **Purpose**: Start the app locally in debug mode
- **Use when**: You want to run the app locally for debugging
- **Environment**: Sets `DEBUG_MODE=true` automatically

## How It Works

### Production Mode (`DEBUG_MODE=false`)
- Uses gunicorn for production deployment
- No debugpy overhead
- Standard Flask app startup

### Debug Mode (`DEBUG_MODE=true`)
- Starts debugpy server on port 5678
- Runs Flask development server with debug mode
- Allows full debugging capabilities
- Flask auto-reload enabled for development

## Debug Features Available

- ✅ Breakpoints
- ✅ Variable inspection
- ✅ Call stack navigation
- ✅ Step-by-step execution
- ✅ Hot reload (with volume mounting)

## Troubleshooting

### Container won't start in debug mode
1. Check if debugpy is installed: `pip install debugpy`
2. Verify port 5678 is not blocked
3. Check container logs for debugpy errors

### VS Code can't connect
1. Ensure container is running with `DEBUG_MODE=true`
2. Verify port 5678 is mapped in docker-compose.yml
3. Check firewall settings

### Breakpoints not hitting
1. Verify path mappings in launch.json
2. Ensure source code is mounted correctly
3. Check if debugpy server is running in container

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG_MODE` | `false` | Enable/disable debug mode |
| `FLASK_HOST` | `0.0.0.0` | Flask app host |
| `FLASK_PORT` | `5001` | Flask app port |

## Ports

| Port | Purpose | Mode |
|------|---------|------|
| 5001 | Flask app | Both |
| 5678 | Debugpy server | Debug only |

## Example Usage

1. **Start container in debug mode**:
   ```bash
   # Edit docker-compose.yml: DEBUG_MODE=true
   docker-compose up --build flask-external
   ```

2. **In VS Code**:
   - Set breakpoints in your Python code
   - Use "Python Flask App (Debug Mode)" configuration
   - Start debugging (F5)

3. **Make requests** to trigger breakpoints:
   ```bash
   curl http://localhost:8081/health
   ```

The debugger will pause at your breakpoints and you can inspect variables, step through code, etc. 