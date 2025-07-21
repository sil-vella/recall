"""
DEPRECATED: This file has been refactored into modular components.

The AppManager class has been split into separate files for better organization:
- app_manager.py: Main orchestrator class
- manager_initializer.py: Handles manager initialization
- middleware_setup.py: Handles Flask middleware setup
- health_checker.py: Handles health checking functionality

Please use the new modular structure instead of this monolithic file.
"""

# Import the new modular AppManager
from .app_manager import AppManager

# For backward compatibility, export the AppManager class
__all__ = ['AppManager']
