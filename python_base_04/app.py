from flask import Flask, request, jsonify
from flask_cors import CORS
from system.managers.app_manager import AppManager
import sys
import os
import importlib
from system.metrics import init_metrics
from utils.config.config import Config
from tools.logger.custom_logging import custom_log

# Clear Python's import cache to prevent stale imports
importlib.invalidate_caches()

sys.path.append(os.path.abspath(os.path.dirname(__file__)))


# Initialize the AppManager
app_manager = AppManager()

# Initialize the Flask app
app = Flask(__name__)

# Enable Cross-Origin Resource Sharing (CORS)
CORS(app)

# Initialize metrics
metrics = init_metrics(app)

# Initialize the AppManager and pass the app for plugin registration
app_manager.initialize(app)

# WebSocket functionality is now handled by app_manager
if app_manager.websocket_manager:
    custom_log("✅ WebSocket manager initialized and ready")
else:
    custom_log("⚠️ WebSocket manager not available")

# Additional app-level configurations
app.config["DEBUG"] = Config.DEBUG

@app.route('/health')
def health_check():
    """Health check endpoint for Kubernetes liveness and readiness probes"""
    custom_log("Health check endpoint called")
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

# @app.route('/actions/<action_name>/<path:args>', methods=['GET', 'POST'])
# def execute_internal_action(action_name, args):
#     """Internal actions route - no authentication required."""
#     try:
#         # Get request data (JSON body for POST, query params for GET)
#         if request.method == 'POST':
#             request_data = request.get_json() or {}
#         else:
#             request_data = dict(request.args)
        
#         # Parse URL arguments
#         parsed_args = app_manager.action_discovery_manager.parse_url_args(args)
        
#         # Merge URL args with request data
#         all_args = {**parsed_args, **request_data}
        
#         # Search for action in YAML registry
#         action_info = app_manager.action_discovery_manager.find_action(action_name)
#         if not action_info:
#             return jsonify({
#                 'error': f'Action "{action_name}" not found',
#                 'available_actions': list(app_manager.action_discovery_manager.actions_registry.keys())
#             }), 404
        
#         # Validate arguments against YAML declaration
#         validation_result = app_manager.action_discovery_manager.validate_action_args(action_info, all_args)
#         if not validation_result['valid']:
#             return jsonify({
#                 'error': 'Invalid arguments',
#                 'details': validation_result['errors'],
#                 'required_params': validation_result['required_params'],
#                 'optional_params': validation_result['optional_params']
#             }), 400
        
#         # Execute action
#         result = app_manager.action_discovery_manager.execute_action_logic(action_info, all_args)
        
#         return jsonify({
#             'success': True,
#             'action': action_name,
#             'module': action_info['module'],
#             'result': result
#         }), 200
        
#     except Exception as e:
#         custom_log(f"❌ Error executing internal action {action_name}: {e}", level="ERROR")
#         return jsonify({'error': f'Action execution failed: {str(e)}'}), 500

# @app.route('/api-auth/actions/<action_name>/<path:args>', methods=['GET', 'POST'])
# def execute_authenticated_action(action_name, args):
#     """Authenticated actions route - requires API key and forwards to credit system."""
#     try:
#         # Get request data (JSON body for POST, query params for GET)
#         if request.method == 'POST':
#             request_data = request.get_json() or {}
#         else:
#             request_data = dict(request.args)
        
#         # Parse URL arguments
#         parsed_args = app_manager.action_discovery_manager.parse_url_args(args)
        
#         # Merge URL args with request data
#         all_args = {**parsed_args, **request_data}
        
#         # Search for action in YAML registry
#         action_info = app_manager.action_discovery_manager.find_action(action_name)
#         if not action_info:
#             return jsonify({
#                 'error': f'Action "{action_name}" not found',
#                 'available_actions': list(app_manager.action_discovery_manager.actions_registry.keys())
#             }), 404
        
#         # Validate arguments against YAML declaration
#         validation_result = app_manager.action_discovery_manager.validate_action_args(action_info, all_args)
#         if not validation_result['valid']:
#             return jsonify({
#                 'error': 'Invalid arguments',
#                 'details': validation_result['errors'],
#                 'required_params': validation_result['required_params'],
#                 'optional_params': validation_result['optional_params']
#             }), 400
        
#         # Forward to credit system with API key
#         credit_system_url = app_manager.action_discovery_manager.app_manager.services_manager.get_credit_system_url()
#         api_key = app_manager.action_discovery_manager.app_manager.services_manager.get_credit_system_api_key()
        
#         if not credit_system_url or not api_key:
#             return jsonify({'error': 'Credit system not configured'}), 500
        
#         # Prepare request to credit system
#         forward_url = f"{credit_system_url}/actions/{action_name}/{args}"
#         headers = {
#             'Authorization': f'Bearer {api_key}',
#             'Content-Type': 'application/json'
#         }
        
#         # Forward the request
#         import requests
#         if request.method == 'POST':
#             response = requests.post(forward_url, json=all_args, headers=headers)
#         else:
#             response = requests.get(forward_url, params=all_args, headers=headers)
        
#         return jsonify(response.json()), response.status_code
        
#     except Exception as e:
#         custom_log(f"❌ Error executing authenticated action {action_name}: {e}", level="ERROR")
#         return jsonify({'error': f'Action execution failed: {str(e)}'}), 500

# @app.route('/actions', methods=['GET'])
# def list_internal_actions():
#     """List all discovered internal actions (no auth required)."""
#     try:
#         result = app_manager.action_discovery_manager.list_all_actions()
#         if result.get('success'):
#             return jsonify(result), 200
#         else:
#             return jsonify(result), 500
#     except Exception as e:
#         custom_log(f"❌ Error listing internal actions: {e}", level="ERROR")
#         return jsonify({'error': f'Failed to list actions: {str(e)}'}), 500

# @app.route('/api-auth/actions', methods=['GET'])
# def list_authenticated_actions():
#     """List all discovered authenticated actions (requires API key)."""
#     try:
#         result = app_manager.action_discovery_manager.list_all_actions()
#         if result.get('success'):
#             return jsonify(result), 200
#         else:
#             return jsonify(result), 500
#     except Exception as e:
#         custom_log(f"❌ Error listing authenticated actions: {e}", level="ERROR")
#         return jsonify({'error': f'Failed to list actions: {str(e)}'}), 500
    

# Production mode: Let gunicorn handle the app
# Development mode: Uncomment below for Flask development server
# if __name__ == "__main__":
#     # Use environment variables for host and port
#     host = os.getenv('FLASK_HOST', '0.0.0.0')
#     port = int(os.getenv('FLASK_PORT', 5001))
#     
#     # WebSocket functionality is now handled by app_manager
#     if app_manager.websocket_manager:
#         custom_log("🚀 Starting Flask app with WebSocket support")
#         app_manager.websocket_manager.run(app, host=host, port=port)
#     else:
#         custom_log("🚀 Starting Flask app without WebSocket support")
#         app_manager.run(app, host=host, port=port)
