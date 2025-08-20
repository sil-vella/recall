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
            custom_log(f"🧹 Cleared server.log file at: {log_file_path}")
        else:
            custom_log(f"📝 server.log file not found at: {log_file_path}, will be created when needed")
    except Exception as e:
        custom_log(f"⚠️ Failed to clear server.log: {e}", level="WARNING")

# Clear the log file on startup
clear_serve_log()

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
app.config["DEBUG"] = True  # Force debug mode for development

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
        custom_log(f"❌ Error executing action {action_name}: {e}", level="ERROR")
        return jsonify({'error': str(e)}), 500

@app.route('/test/recall-join-game', methods=['POST'])
def test_recall_join_game():
    """Test endpoint to trigger recall_join_game event"""
    try:
        data = request.get_json() or {}
        
        # Get required parameters
        session_id = data.get('session_id', 'test_session_123')
        game_id = data.get('game_id', 'test_game_456')
        player_name = data.get('player_name', 'TestPlayer')
        player_type = data.get('player_type', 'human')
        
        # Create test event data
        event_data = {
            'session_id': session_id,
            'game_id': game_id,
            'player_name': player_name,
            'player_type': player_type
        }
        
        # Get the recall gameplay manager from app manager
        recall_main = app_manager.get_recall_game_main()
        if not recall_main or not recall_main.recall_gameplay_manager:
            return jsonify({'error': 'Recall gameplay manager not found'}), 500
        
        # Trigger the event handler directly
        result = recall_main.recall_gameplay_manager.on_join_game(session_id, event_data)
        
        if result:
            return jsonify({
                'success': True,
                'message': 'recall_join_game event triggered successfully',
                'data': event_data
            }), 200
        else:
            return jsonify({
                'success': False,
                'message': 'Failed to trigger recall_join_game event',
                'data': event_data
            }), 500
            
    except Exception as e:
        custom_log(f"❌ Error in test_recall_join_game: {e}", level="ERROR")
        return jsonify({'error': f'Test failed: {str(e)}'}), 500

@app.route('/test/recall-start-match', methods=['POST'])
def test_recall_start_match():
    """Test endpoint to trigger recall_start_match event"""
    try:
        data = request.get_json() or {}
        
        # Get required parameters
        session_id = data.get('session_id', 'test_session_123')
        game_id = data.get('game_id', 'test_game_456')
        
        # Create test event data
        event_data = {
            'game_id': game_id,
            'room_id': game_id  # Some clients send room_id instead of game_id
        }
        
        # Get the recall gameplay manager from app manager
        recall_main = app_manager.get_recall_game_main()
        if not recall_main or not recall_main.recall_gameplay_manager:
            return jsonify({'error': 'Recall gameplay manager not found'}), 500
        
        # Trigger the event handler directly
        result = recall_main.recall_gameplay_manager.on_start_match(session_id, event_data)
        
        if result:
            return jsonify({
                'success': True,
                'message': 'recall_start_match event triggered successfully',
                'data': event_data
            }), 200
        else:
            return jsonify({
                'success': False,
                'message': 'Failed to trigger recall_start_match event',
                'data': event_data
            }), 500
            
    except Exception as e:
        custom_log(f"❌ Error in test_recall_start_match: {e}", level="ERROR")
        return jsonify({'error': f'Test failed: {str(e)}'}), 500

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
        custom_log(f"❌ Error in frontend_log: {e}", level="ERROR")
        return jsonify({'error': f'Log failed: {str(e)}'}), 500

# Development server startup
if __name__ == "__main__":
    # Use environment variables for host and port
    host = os.getenv('FLASK_HOST', '0.0.0.0')
    port = int(os.getenv('FLASK_PORT', 5001))
    
    custom_log(f"🚀 Starting Flask DEBUG server on {host}:{port}")
    
    # WebSocket functionality is now handled by app_manager
    if app_manager.websocket_manager:
        custom_log("🚀 Starting Flask app with WebSocket support")
        app_manager.websocket_manager.run(app, host=host, port=port, debug=True)
    else:
        custom_log("🚀 Starting Flask app without WebSocket support")
        app_manager.run(app, host=host, port=port, debug=True)
