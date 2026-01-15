from flask import Flask, request, jsonify
from flask_cors import CORS
from core.managers.app_manager import AppManager
import sys
import os
import importlib
from core.metrics import init_metrics
from utils.config.config import Config
from tools.logger.custom_logging import custom_log

# Test logging control
LOGGING_SWITCH = False  # Enabled for rank-based matching and debugging

# Clear Python's import cache to prevent stale imports
importlib.invalidate_caches()

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

# Clear serve.log on initialization (only if not recently cleared)
def clear_serve_log():
    """Clear the server.log file on debug app initialization (smart clearing)"""
    try:
        # Use the correct path to server.log
        log_file_path = os.path.join(os.path.dirname(__file__), 'tools', 'logger', 'server.log')
        
        # Check if file exists and when it was last modified
        if os.path.exists(log_file_path):
            # Get file modification time
            import time
            file_mtime = os.path.getmtime(log_file_path)
            current_time = time.time()
            
            # Only clear if file is older than 30 seconds (prevents multiple clears in quick succession)
            if (current_time - file_mtime) > 30:
                with open(log_file_path, 'w') as f:
                    f.write('')
                custom_log("Server log cleared on startup", isOn=LOGGING_SWITCH)
            else:
                custom_log("Server log not cleared - recently modified", isOn=LOGGING_SWITCH)
        else:
            # Create empty file if it doesn't exist
            with open(log_file_path, 'w') as f:
                f.write('')
            custom_log("Server log file created", isOn=LOGGING_SWITCH)
    except Exception as e:
        custom_log(f"Error managing server log: {e}", isOn=LOGGING_SWITCH)

# Clear the log file on startup (smart clearing)
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

@app.route('/metrics')
def metrics_endpoint():
    """
    Expose Prometheus metrics through Flask route.
    
    This ensures metrics are always read from the current process's REGISTRY,
    avoiding issues with Flask's debug reloader creating new processes.
    The separate HTTP server on port 8000 is kept as a fallback for production.
    
    This endpoint is the PRIMARY way to expose metrics in development (Flask debug mode).
    Prometheus should scrape this endpoint instead of the separate HTTP server.
    """
    from prometheus_client import generate_latest, REGISTRY
    from flask import Response, request
    
    try:
        custom_log(f"Flask /metrics endpoint: Request from {request.remote_addr}, User-Agent: {request.headers.get('User-Agent', 'unknown')}", isOn=LOGGING_SWITCH)
        
        # Generate metrics from current process's REGISTRY
        # This always reads from the current Flask process, not a stale one
        metrics_output = generate_latest(REGISTRY)
        
        # Log detailed metrics info for debugging
        if LOGGING_SWITCH:
            output_str = metrics_output.decode('utf-8')
            user_logins_lines = [l for l in output_str.split('\n') 
                               if 'user_logins_total' in l and not l.startswith('#') and l.strip()]
            user_regs_lines = [l for l in output_str.split('\n') 
                             if 'user_registrations_total' in l and not l.startswith('#') and l.strip()]
            flask_reqs_lines = [l for l in output_str.split('\n') 
                              if 'flask_app_requests_total' in l and not l.startswith('#') and l.strip()]
            
            custom_log(f"Flask /metrics endpoint: REGISTRY id={id(REGISTRY)}, output size={len(output_str)} bytes", isOn=LOGGING_SWITCH)
            custom_log(f"Flask /metrics endpoint: user_logins_total={len(user_logins_lines)} lines, user_registrations_total={len(user_regs_lines)} lines, flask_app_requests_total={len(flask_reqs_lines)} lines", isOn=LOGGING_SWITCH)
            
            if user_logins_lines:
                custom_log(f"Flask /metrics endpoint: Sample user_logins_total line: {user_logins_lines[0][:100]}", isOn=LOGGING_SWITCH)
            if flask_reqs_lines:
                custom_log(f"Flask /metrics endpoint: Sample flask_app_requests_total line: {flask_reqs_lines[0][:100]}", isOn=LOGGING_SWITCH)
        
        return Response(
            metrics_output,
            mimetype='text/plain; version=0.0.4; charset=utf-8'
        )
    except Exception as e:
        custom_log(f"Flask /metrics endpoint: Error generating metrics: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        import traceback
        custom_log(f"Flask /metrics endpoint: Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({
            'success': False,
            'error': f'Failed to generate metrics: {str(e)}'
        }), 500

@app.route('/metrics/verify')
def verify_metrics():
    """Verify metrics are in REGISTRY and accessible via HTTP server."""
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
    
    # Test custom_log with isOn parameter
    custom_log("App debug server starting up", level="INFO", isOn=LOGGING_SWITCH)
    
    # WebSocket functionality is now handled by app_manager
    if app_manager.websocket_manager:
        app_manager.websocket_manager.run(app, host=host, port=port, debug=True)
    else:
        app_manager.run(app, host=host, port=port, debug=True)
