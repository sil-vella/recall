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

def ensure_server_log_file_exists():
    """Ensure tools/logger/server.log exists; never truncate (append-only shared log)."""
    try:
        log_file_path = os.path.join(os.path.dirname(__file__), "tools", "logger", "server.log")
        os.makedirs(os.path.dirname(log_file_path), exist_ok=True)
        if not os.path.exists(log_file_path):
            open(log_file_path, "a", encoding="utf-8").close()
    except Exception:
        pass


def setup_server_log_file_handler():
    """Append Werkzeug and root Python logging to tools/logger/server.log (shared with Flutter/Dart)."""
    import logging
    from datetime import datetime, timezone

    log_path = os.path.join(os.path.dirname(__file__), "tools", "logger", "server.log")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    abs_path = os.path.abspath(log_path)
    root = logging.getLogger()
    for h in root.handlers:
        bf = getattr(h, "baseFilename", None)
        if bf and os.path.abspath(bf) == abs_path:
            return

    class UtcFormatter(logging.Formatter):
        def formatTime(self, record, datefmt=None):
            return datetime.fromtimestamp(record.created, tz=timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            )

    fh = logging.FileHandler(abs_path, mode="a", encoding="utf-8")
    fh.setLevel(logging.INFO)
    fh.setFormatter(
        UtcFormatter("%(asctime)s [PYTHON] %(levelname)s %(name)s: %(message)s")
    )
    root.addHandler(fh)
    root.setLevel(logging.INFO)
    logging.getLogger("werkzeug").setLevel(logging.INFO)


ensure_server_log_file_exists()
setup_server_log_file_handler()

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


@app.route('/log', methods=['POST'])
def frontend_log():
    """Append Flutter (and other client) lines to server.log — same format as launch script [FLUTTER] lines."""
    try:
        from datetime import datetime, timezone

        data = request.get_json() or {}
        message = (data.get("message", "") or "").replace("\r\n", "\n").replace("\n", " ").strip()
        log_file_path = os.path.join(os.path.dirname(__file__), "tools", "logger", "server.log")
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        log_entry = f"{ts} [FLUTTER] {message}\n"
        with open(log_file_path, "a", encoding="utf-8") as f:
            f.write(log_entry)
        
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
