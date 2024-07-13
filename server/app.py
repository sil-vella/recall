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
app = Flask(__name__, static_folder='../client/build', static_url_path='')
app.secret_key = 'its_a_secret_key'

# Enable CORS for all origins
CORS(app, resources={r"/*": {"origins": "*"}})

# Use setup_socketio to instantiate and configure your SocketIO instance
socketio = setup_socketio(app)

# Initialize EventManager
event_manager = EventManager(socketio)

# Example route
@app.route('/')
def index():
    return render_template('index.html')

if __name__ == '__main__':
    socketio.run(app)
