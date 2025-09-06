from flask import Flask, request, jsonify
from flask_cors import CORS
from core.managers.app_manager import AppManager
import sys
import os
import importlib
from core.metrics import init_metrics
from utils.config.config import Config
from tools.logger.custom_logging import custom_log

# Clear Python's import cache to prevent stale imports
importlib.invalidate_caches()

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

# Clear serve.log on initialization
def clear_serve_log():
    """Clear the server.log file on debug app initialization"""
    try:
        # Use the correct path to server.log
        log_file_path = os.path.join(os.path.dirname(__file__), 'tools', 'logger', 'server.log')
        if os.path.exists(log_file_path):
            # Clear the file by opening in write mode and truncating
            with open(log_file_path, 'w') as f:
                f.write('')
        else:
            pass
    except Exception as e:
        pass

# Clear the log file on startup
clear_serve_log()

# Initialize the AppManager
app_manager = AppManager()

# Initialize the Flask app
app = Flask(__name__)

# Enable Cross-Origin Resource Sharing (CORS)
# Allow requests from Flutter web app and other local development ports
CORS(app, 
    origins=[
        "http://localhost:3000",
        "http://localhost:3001", 
        "http://localhost:3002",
        "http://localhost:3003",
        "http://localhost:3004",
        "http://localhost:3005",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:3001",
        "http://127.0.0.1:3002",
        "http://127.0.0.1:3003",
        "http://127.0.0.1:3004",
        "http://127.0.0.1:3005",
    ], 
    supports_credentials=True,
    allow_headers=["*"],
    methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    expose_headers=["*"]
)

# Initialize metrics
metrics = init_metrics(app)

# Initialize the AppManager and pass the app for plugin registration
app_manager.initialize(app)

# WebSocket functionality is now handled by app_manager
if app_manager.websocket_manager:
    pass
else:
    pass

# Additional app-level configurations
app.config["DEBUG"] = True  # Force debug mode for development

@app.route('/health')
def health_check():
    """Health check endpoint for Kubernetes liveness and readiness probes"""
    try:
        # Check if the application is properly initialized
        if not app_manager.is_initialized():
            return {'status': 'unhealthy', 'reason': 'App manager not initialized'}, 503
            
        # Check database connection
        if not app_manager.check_database_connection():
            return {'status': 'unhealthy', 'reason': 'Database connection failed'}, 503
            
        # Check Redis connection
        if not app_manager.check_redis_connection():
            return {'status': 'unhealthy', 'reason': 'Redis connection failed'}, 503
        
        # Check state manager status
        state_manager_health = app_manager.state_manager.health_check()
        if state_manager_health.get('status') != 'healthy':
            return {'status': 'unhealthy', 'reason': 'State manager unhealthy'}, 503
        
        # Check module status
        module_status = app_manager.module_manager.get_module_status()
        unhealthy_modules = []
        
        for module_key, module_info in module_status.get('modules', {}).items():
            if module_info.get('health', {}).get('status') != 'healthy':
                unhealthy_modules.append(module_key)
        
        if unhealthy_modules:
            return {
                'status': 'degraded', 
                'reason': f'Unhealthy modules: {unhealthy_modules}',
                'module_status': module_status
            }, 200  # Still return 200 for degraded but functional
            
        return {
            'status': 'healthy',
            'modules_initialized': module_status.get('initialized_modules', 0),
            'total_modules': module_status.get('total_modules', 0),
            'state_manager': state_manager_health
        }, 200
    except Exception as e:
        return {'status': 'unhealthy', 'reason': str(e)}, 503

@app.route('/actions/<action_name>/<path:args>', methods=['GET', 'POST'])
def execute_internal_action(action_name, args):
    """Internal actions route - no authentication required."""
    try:
        # Get request data (JSON body for POST, query params for GET)
        if request.method == 'POST':
            request_data = request.get_json() or {}
        else:
            request_data = dict(request.args)
        
        # Parse URL arguments
        parsed_args = app_manager.action_discovery_manager.parse_url_args(args)
        
        # Merge URL args with request data
        merged_data = {**parsed_args, **request_data}
        
        # Execute the action
        result = app_manager.action_discovery_manager.execute_action_logic(
            action_name, merged_data
        )
        
        return jsonify(result)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/log', methods=['POST'])
def frontend_log():
    """Simple endpoint to catch frontend logs and append to server.log"""
    try:
        data = request.get_json() or {}
        
        # Extract log data
        message = data.get('message', '')
        level = data.get('level', 'INFO')
        source = data.get('source', 'frontend')
        platform = data.get('platform', 'flutter')
        build_mode = data.get('buildMode', 'debug')
        timestamp = data.get('timestamp', '')
        
        # Format the log message
        log_entry = f"[{timestamp}] - {source} - {level} - [{platform}|{build_mode}] {message}"
        
        # Append to server.log
        log_file_path = os.path.join(os.path.dirname(__file__), 'tools', 'logger', 'server.log')
        with open(log_file_path, 'a') as f:
            f.write(log_entry + '\n')
        
        return jsonify({'success': True, 'message': 'Log recorded'}), 200
        
    except Exception as e:
        return jsonify({'error': f'Log failed: {str(e)}'}), 500

# Development server startup
if __name__ == "__main__":
    # Use environment variables for host and port
    host = os.getenv('FLASK_HOST', '0.0.0.0')
    port = int(os.getenv('FLASK_PORT', 5001))
    
    # WebSocket functionality is now handled by app_manager
    if app_manager.websocket_manager:
        app_manager.websocket_manager.run(app, host=host, port=port, debug=True)
    else:
        app_manager.run(app, host=host, port=port, debug=True)
