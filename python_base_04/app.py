from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from core.managers.app_manager import AppManager
import sys
import os
import importlib
from core.metrics import init_metrics
from utils.config.config import Config
from tools.logger.custom_logging import custom_log

# Logging switch for optional verbose metrics/logging
LOGGING_SWITCH = Config.DEBUG

# Clear Python's import cache to prevent stale imports
importlib.invalidate_caches()

sys.path.append(os.path.abspath(os.path.dirname(__file__)))


# Initialize the AppManager
app_manager = AppManager()

# Initialize the Flask app
app = Flask(__name__)

# Enable Cross-Origin Resource Sharing (CORS)
# Production: Allow requests from reignofplay.com domains
# Development: Use app.debug.py with localhost origins
if Config.DEBUG:
    # Development mode - allow all origins for flexibility
    CORS(app)
else:
    # Production mode - restrict to reignofplay.com domains
    # plus allow local Flutter web dev origins for testing
    CORS(app,
        origins=[
            "https://reignofplay.com",
            "https://www.reignofplay.com",
            "https://cleco.reignofplay.com",
            "http://localhost:3002",
            "http://127.0.0.1:3002",
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
app.config["DEBUG"] = Config.DEBUG

@app.route('/metrics')
def metrics_endpoint():
    """
    Expose Prometheus metrics through Flask route.
    
    This mirrors the behavior in app.debug.py so that Prometheus/Grafana
    can scrape metrics from the production container as well.
    """
    from prometheus_client import generate_latest, REGISTRY
    
    try:
        custom_log(
            f"Flask /metrics endpoint: Request from {request.remote_addr}, "
            f"User-Agent: {request.headers.get('User-Agent', 'unknown')}",
            isOn=LOGGING_SWITCH
        )
        
        # Generate metrics from current process's REGISTRY
        metrics_output = generate_latest(REGISTRY)
        
        # Optional detailed logging in debug mode
        if LOGGING_SWITCH:
            output_str = metrics_output.decode('utf-8')
            user_logins_lines = [
                l for l in output_str.split('\n')
                if 'user_logins_total' in l and not l.startswith('#') and l.strip()
            ]
            user_regs_lines = [
                l for l in output_str.split('\n')
                if 'user_registrations_total' in l and not l.startswith('#') and l.strip()
            ]
            flask_reqs_lines = [
                l for l in output_str.split('\n')
                if 'flask_app_requests_total' in l and not l.startswith('#') and l.strip()
            ]
            
            custom_log(
                f"Flask /metrics endpoint: REGISTRY id={id(REGISTRY)}, "
                f"output size={len(output_str)} bytes",
                isOn=LOGGING_SWITCH
            )
            custom_log(
                "Flask /metrics endpoint: "
                f"user_logins_total={len(user_logins_lines)} lines, "
                f"user_registrations_total={len(user_regs_lines)} lines, "
                f"flask_app_requests_total={len(flask_reqs_lines)} lines",
                isOn=LOGGING_SWITCH
            )
            
            if user_logins_lines:
                custom_log(
                    "Flask /metrics endpoint: Sample user_logins_total line: "
                    f"{user_logins_lines[0][:100]}",
                    isOn=LOGGING_SWITCH
                )
            if flask_reqs_lines:
                custom_log(
                    "Flask /metrics endpoint: Sample flask_app_requests_total line: "
                    f"{flask_reqs_lines[0][:100]}",
                    isOn=LOGGING_SWITCH
                )
        
        return Response(
            metrics_output,
            mimetype='text/plain; version=0.0.4; charset=utf-8'
        )
    except Exception as e:
        custom_log(
            f"Flask /metrics endpoint: Error generating metrics: {e}",
            level="ERROR",
            isOn=LOGGING_SWITCH
        )
        import traceback
        custom_log(
            f"Flask /metrics endpoint: Traceback: {traceback.format_exc()}",
            level="ERROR",
            isOn=LOGGING_SWITCH
        )
        return jsonify({
            'success': False,
            'error': f'Failed to generate metrics: {str(e)}'
        }), 500

@app.route('/metrics/verify')
def verify_metrics():
    """
    Verify metrics are in REGISTRY and accessible via the metrics HTTP server.
    Mirrors the debug app helper so you can sanity-check metrics in prod.
    """
    try:
        metrics_collector = app_manager.get_metrics_collector()
        if metrics_collector:
            result = metrics_collector.verify_http_server_registry()
            return jsonify({
                'success': True,
                'registry_check': result,
                'message': 'Metrics registry verification completed'
            }), 200
        else:
            return jsonify({
                'success': False,
                'error': 'MetricsCollector not available'
            }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

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
        try:
            state_manager_health = app_manager.state_manager.health_check()
        except Exception as e:
            return {
                'status': 'unhealthy',
                'reason': f'State manager health check failed: {str(e)}'
            }, 503

        if state_manager_health.get('status') != 'healthy':
            return {'status': 'unhealthy', 'reason': 'State manager unhealthy'}, 503

        # Lightweight module status overview (avoid deep or recursive health checks)
        module_manager = app_manager.module_manager
        modules = getattr(module_manager, 'modules', {})

        module_summary = {}
        uninitialized_modules = []

        for module_key, module_instance in modules.items():
            is_initialized = True
            if hasattr(module_instance, 'is_initialized'):
                try:
                    is_initialized = bool(module_instance.is_initialized())
                except Exception:
                    is_initialized = False

            module_summary[module_key] = {
                'initialized': is_initialized,
                'class': module_instance.__class__.__name__,
            }

            if not is_initialized:
                uninitialized_modules.append(module_key)

        overall_status = 'healthy' if not uninitialized_modules else 'degraded'

        return {
            'status': overall_status,
            'modules_initialized': len(modules) - len(uninitialized_modules),
            'total_modules': len(modules),
            'uninitialized_modules': uninitialized_modules,
            'state_manager': state_manager_health,
            'modules': module_summary,
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
        all_args = {**parsed_args, **request_data}
        
        # Search for action in YAML registry
        action_info = app_manager.action_discovery_manager.find_action(action_name)
        if not action_info:
            return jsonify({
                'error': f'Action "{action_name}" not found',
                'available_actions': list(app_manager.action_discovery_manager.actions_registry.keys())
            }), 404
        
        # Validate arguments against YAML declaration
        validation_result = app_manager.action_discovery_manager.validate_action_args(action_info, all_args)
        if not validation_result['valid']:
            return jsonify({
                'error': 'Invalid arguments',
                'details': validation_result['errors'],
                'required_params': validation_result['required_params'],
                'optional_params': validation_result['optional_params']
            }), 400
        
        # Execute action
        result = app_manager.action_discovery_manager.execute_action_logic(action_info, all_args)
        
        return jsonify({
            'success': True,
            'action': action_name,
            'module': action_info['module'],
            'result': result
        }), 200
        
    except Exception as e:
        return jsonify({'error': f'Action execution failed: {str(e)}'}), 500

@app.route('/api-auth/actions/<action_name>/<path:args>', methods=['GET', 'POST'])
def execute_authenticated_action(action_name, args):
    """Authenticated actions route - requires API key and forwards to credit system."""
    try:
        # Get request data (JSON body for POST, query params for GET)
        if request.method == 'POST':
            request_data = request.get_json() or {}
        else:
            request_data = dict(request.args)
        
        # Parse URL arguments
        parsed_args = app_manager.action_discovery_manager.parse_url_args(args)
        
        # Merge URL args with request data
        all_args = {**parsed_args, **request_data}
        
        # Search for action in YAML registry
        action_info = app_manager.action_discovery_manager.find_action(action_name)
        if not action_info:
            return jsonify({
                'error': f'Action "{action_name}" not found',
                'available_actions': list(app_manager.action_discovery_manager.actions_registry.keys())
            }), 404
        
        # Validate arguments against YAML declaration
        validation_result = app_manager.action_discovery_manager.validate_action_args(action_info, all_args)
        if not validation_result['valid']:
            return jsonify({
                'error': 'Invalid arguments',
                'details': validation_result['errors'],
                'required_params': validation_result['required_params'],
                'optional_params': validation_result['optional_params']
            }), 400
        
        # Forward to credit system with API key
        credit_system_url = app_manager.action_discovery_manager.app_manager.services_manager.get_credit_system_url()
        api_key = app_manager.action_discovery_manager.app_manager.services_manager.get_credit_system_api_key()
        
        if not credit_system_url or not api_key:
            return jsonify({'error': 'Credit system not configured'}), 500
        
        # Prepare request to credit system
        forward_url = f"{credit_system_url}/actions/{action_name}/{args}"
        headers = {
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        }
        
        # Forward the request
        import requests
        if request.method == 'POST':
            response = requests.post(forward_url, json=all_args, headers=headers)
        else:
            response = requests.get(forward_url, params=all_args, headers=headers)
        
        return jsonify(response.json()), response.status_code
        
    except Exception as e:
        return jsonify({'error': f'Action execution failed: {str(e)}'}), 500

@app.route('/actions', methods=['GET'])
def list_internal_actions():
    """List all discovered internal actions (no auth required)."""
    try:
        result = app_manager.action_discovery_manager.list_all_actions()
        if result.get('success'):
            return jsonify(result), 200
        else:
            return jsonify(result), 500
    except Exception as e:
        return jsonify({'error': f'Failed to list actions: {str(e)}'}), 500

@app.route('/log', methods=['POST'])
def frontend_log():
    """
    Simple endpoint to catch frontend logs and append to server.log.
    Brought over from app.debug.py so production can also capture client logs.
    """
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
        log_file_path = os.path.join(
            os.path.dirname(__file__),
            'tools', 'logger', 'server.log'
        )
        with open(log_file_path, 'a') as f:
            f.write(log_entry + '\n')
        
        return jsonify({'success': True, 'message': 'Log recorded'}), 200
        
    except Exception as e:
        return jsonify({'error': f'Log failed: {str(e)}'}), 500

@app.route('/api-auth/actions', methods=['GET'])
def list_authenticated_actions():
    """List all discovered authenticated actions (requires API key)."""
    try:
        result = app_manager.action_discovery_manager.list_all_actions()
        if result.get('success'):
            return jsonify(result), 200
        else:
            return jsonify(result), 500
    except Exception as e:
        return jsonify({'error': f'Failed to list actions: {str(e)}'}), 500

# Test endpoints removed - Cleco game is now managed through ModuleRegistry
    

# Production mode: Let gunicorn handle the app
# Development mode: Use app.debug.py for local development
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
