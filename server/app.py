import os
import sys
from flask import Flask, render_template
from flask_socketio import SocketIO
from flask_cors import CORS
from game_logic.game_utilities.event_manager import setup_socketio, EventManager
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED

if FUNCTION_LOGGING_ENABLED:
    current_module = sys.modules[__name__]
    add_logging_to_module(current_module, exclude_instances=[Flask, SocketIO, CORS], exclude_packages=['flask', 'flask_cors', 'flask_socketio'])

# Flask app setup
custom_log('Setting up Flask app...')
app = Flask(__name__, static_folder='../client/build', static_url_path='')
app.secret_key = 'its_a_secret_key'

# Enable CORS for all origins
custom_log('Enabling CORS...')
CORS(app, resources={r"/*": {"origins": "*"}})

# Use setup_socketio to instantiate and configure your SocketIO instance
custom_log('Setting up SocketIO...')
socketio = setup_socketio(app)

# Initialize EventManager
custom_log('Initializing EventManager...')
event_manager = EventManager(socketio)

# Example route
@app.route('/')
def index():
    custom_log('Rendering index.html...')
    return render_template('index.html')

# Debugging SocketIO events
@socketio.on('connect')
def handle_connect():
    custom_log('Client connected')

@socketio.on('disconnect')
def handle_disconnect():
    custom_log('Client disconnected')

@socketio.on('error')
def handle_error(error):
    custom_log(f'Socket error: {error}')

@socketio.on('custom_event')
def handle_custom_event(data):
    custom_log(f'Custom event received with data: {data}')
    # Handle the custom event using event_manager or other logic
    event_manager.handle_event('custom_event', data)

def log_server_started(port):
    custom_log(f'Flask app with SocketIO has started and is running on port {port}.')

if __name__ == '__main__':
    port = 5000  # You can customize this port number if needed
    custom_log(f'Flask app with SocketIO is starting on port {port}...')
    socketio.run(app, host='0.0.0.0', port=port, debug=True)
    log_server_started(port)
