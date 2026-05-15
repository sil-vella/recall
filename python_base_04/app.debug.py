from flask import Flask, request, jsonify
from flask_cors import CORS
from core.managers.app_manager import AppManager
import sys
import os
import importlib
from core.metrics import init_metrics
from utils.config.config import Config

# Clear Python's import cache to prevent stale imports
importlib.invalidate_caches()

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from tools.dev_logger import customlog

# Set False when not debugging this entrypoint (release tooling may flip).
LOGGING_SWITCH = True
if LOGGING_SWITCH:
    customlog("app.debug.py entry")

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
        metrics_output = generate_latest(REGISTRY)
        return Response(
            metrics_output,
            mimetype='text/plain; version=0.0.4; charset=utf-8'
        )
    except Exception as e:
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

def _health_check_impl():
    """Shared health check logic for /health and /service/health. Returns (dict, status_code)."""
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


@app.route('/health')
def health_check():
    """Health check endpoint for Kubernetes liveness and readiness probes (public)."""
    data, status = _health_check_impl()
    return jsonify(data), status


@app.route('/service/health', methods=['GET'])
def service_health_check():
    """Health check for service callers (e.g. PHP dashboard). Requires X-Service-Key (Dart or dashboard)."""
    data, status = _health_check_impl()
    return jsonify(data), status

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


# Development server startup
if __name__ == "__main__":
    # Use environment variables for host and port
    host = os.getenv('FLASK_HOST', '0.0.0.0')
    port = int(os.getenv('FLASK_PORT', 5001))

    # With debug=True, Flask-SocketIO defaults use_reloader=True. The Werkzeug reloader
    # stops the child with sys.exit(3); debugpy reports that as an exception. For this
    # IDE entrypoint, disable the reloader unless FLASK_USE_RELOADER=1/true/yes.
    _use_reloader = os.environ.get("FLASK_USE_RELOADER", "").lower() in (
        "1",
        "true",
        "yes",
    )

    # WebSocket functionality is now handled by app_manager
    if app_manager.websocket_manager:
        app_manager.websocket_manager.run(
            app,
            host=host,
            port=port,
            debug=True,
            use_reloader=_use_reloader,
        )
    else:
        app_manager.run(
            app,
            host=host,
            port=port,
            debug=True,
            use_reloader=_use_reloader,
        )
