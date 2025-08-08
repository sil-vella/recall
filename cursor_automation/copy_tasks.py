#!/usr/bin/env python3
import os
import shutil
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def copy_tasks_directory():
    try:
        # Get the source directory (same directory as this script)
        source_dir = Path(__file__).parent / 'tasks'
        
        # Define target directory
        target_dir = Path('/Users/sil/Documents/Work/00Utilities/cursor_automation/servers/execution-mcp/tasks')
        
        # Check if source directory exists
        if not source_dir.exists():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")
        
        logger.info(f"Source directory: {source_dir}")
        logger.info(f"Target directory: {target_dir}")
        
        # Create target parent directory if it doesn't exist
        target_dir.parent.mkdir(parents=True, exist_ok=True)
        
        # Remove target directory if it exists
        if target_dir.exists():
            logger.info("Removing existing target directory...")
            shutil.rmtree(target_dir)
        
        # Copy the directory
        logger.info("Copying tasks directory...")
        shutil.copytree(source_dir, target_dir)
        
        logger.info("✅ Tasks directory successfully copied!")
        
    except FileNotFoundError as e:
        logger.error(f"❌ Error: {e}")
        raise
    except PermissionError as e:
        logger.error(f"❌ Permission error: {e}")
        raise
    except Exception as e:
        logger.error(f"❌ Unexpected error: {e}")
        raise

if __name__ == "__main__":
    try:
        copy_tasks_directory()
    except Exception as e:
        logger.error(f"Failed to copy tasks directory: {e}")
        exit(1)
