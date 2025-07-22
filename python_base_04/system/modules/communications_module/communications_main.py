import os
import json
from tools.logger.custom_logging import custom_log, log_function_call
from utils.config.config import Config
from system.managers.redis_manager import RedisManager
from system.managers.database_manager import DatabaseManager
from system.managers.api_key_manager import APIKeyManager
from tools.error_handling import ErrorHandler
from datetime import datetime, timedelta
import time
import uuid
import logging
from flask import request, jsonify
from typing import Dict, Any
from system.modules.base_module import BaseModule
import debugpy

class CommunicationsModule:
    def __init__(self, db_manager: DatabaseManager, redis_manager: RedisManager, api_key_manager: APIKeyManager):
        self.db_manager = db_manager
        self.redis_manager = redis_manager
        self.api_key_manager = api_key_manager
        custom_log("CommunicationsModule created with explicit dependencies")

    def initialize(self):
        # Initialization logic if needed
        pass

    def register_routes(self):
        """Register all CommunicationsModule routes."""
        custom_log("Registering CommunicationsModule routes...")
        
        from flask import current_app
        
                # Register core routes
        current_app.add_url_rule("/", "home", self.home, methods=["GET"])
        
        custom_log("✅ CommunicationsModule routes registered directly with Flask")

    def home(self):
        """Handle the root route."""
        return {"message": "CommunicationsModule module is running", "version": "2.0", "module": "communications_module"}





    def health_check(self) -> Dict[str, Any]:
        """Perform health check for CommunicationsModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        # Add database queue status
        try:
            queue_status = self.db_manager.get_queue_status()
            health_status['details'] = {
                'database_queue': {
                    'queue_size': queue_status['queue_size'],
                    'worker_alive': queue_status['worker_alive'],
                    'queue_enabled': queue_status['queue_enabled'],
                    'pending_results': queue_status['pending_results']
                },
                'api_key_manager': {
                    'status': 'operational',
                    'external_app_key_configured': bool(self.api_key_manager.load_credit_system_api_key())
                }
            }
        except Exception as e:
            health_status['details'] = {
                'database_queue': f'error: {str(e)}',
                'api_key_manager': {
                    'status': 'operational',
                    'external_app_key_configured': bool(self.api_key_manager.load_credit_system_api_key())
                }
            }
        
        return health_status