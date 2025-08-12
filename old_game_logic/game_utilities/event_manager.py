import threading
import random
import sys
from flask import request
from flask_socketio import SocketIO
from flask_cors import CORS
from game_logic.game_management.game_manager import GameManager
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED

# Ensure logging is added dynamically before any instances are created
if FUNCTION_LOGGING_ENABLED:
    current_module = sys.modules[__name__]
    add_logging_to_module(current_module, exclude_instances=[SocketIO, CORS], exclude_packages=['flask', 'flask_cors', 'flask_socketio'])


class EventManager:
    def __init__(self, socketio):
        self.socketio = socketio
        self.game_manager = GameManager(self)  # Ensure the logging is applied to this instance
        self.emitted_events = set()
        self.event_queue = []
        self.replies = {}
        self.lock = threading.Condition()

    def emit_event(self, event_name, data=None, rooms=None, wait_for=None, expect_reply=False, timeout=None):
        custom_log(f"Attempting to emit event: {event_name} with data: {data}, rooms: {rooms}, wait_for: {wait_for}, expect_reply: {expect_reply}, timeout: {timeout}")
        if not rooms:
            raise ValueError("Rooms must be specified for emitting events.")

        unique_id = None
        if wait_for:
            if not isinstance(wait_for, list):
                wait_for = [wait_for]
            if not all(event in self.emitted_events for event in wait_for):
                self.event_queue.append((event_name, data, rooms, wait_for))
                custom_log(f"Queued event {event_name} waiting for {wait_for}")
                return None

        try:
            custom_log(f"Emitting event {event_name} with data: {data}")

            if data is None:
                data = {}

            if expect_reply:
                unique_id = f"{random.randint(100000, 999999)}"
                data['unique_id'] = unique_id

            if rooms:
                if not isinstance(rooms, list):
                    rooms = [rooms]
                for room in rooms:
                    custom_log(f"Emitting event {event_name} to room {room}")
                    self.socketio.emit(event_name, data, room=room)
            else:
                self.socketio.emit(event_name, data)

            self.emitted_events.add(event_name)
            custom_log(f"Event {event_name} emitted")
            self.process_event_queue()

            if expect_reply and unique_id:
                custom_log(f"Expecting reply for event {event_name} with unique_id {unique_id}")
                timer = threading.Timer(timeout, self.mark_event_as_replied, args=[unique_id])
                timer.start()

                with self.lock:
                    reply_received = self.lock.wait_for(lambda: self.check_event_reply(unique_id), timeout=timeout)

                reply_status = self.replies.pop(unique_id, None)
                timer.cancel()

                if reply_received:
                    if reply_status == 'timeout':
                        custom_log(f"Event {event_name} processed with unique_id {unique_id} (timeout)")
                    else:
                        custom_log(f"Event {event_name} processed with unique_id {unique_id} (reply received)")
                else:
                    custom_log(f"Event {event_name} processed with unique_id {unique_id} (no reply)")

                return unique_id

        except Exception as e:
            custom_log(f"Error emitting event {event_name}: {str(e)}")
            return None

    def process_event_queue(self):
        temp_queue = self.event_queue[:]
        self.event_queue = []
        for event in temp_queue:
            event_name, data, rooms, wait_for = event
            if all(event in self.emitted_events for event in wait_for):
                custom_log(f"Processing queued event {event_name} after all {wait_for} were emitted")
                self.emit_event(event_name, data, rooms)
            else:
                self.event_queue.append(event)

    def check_event_reply(self, unique_id):
        with self.lock:
            return self.replies.get(unique_id, False)

    def mark_event_as_replied(self, unique_id):
        with self.lock:
            self.replies[unique_id] = True
            self.lock.notify_all()

    def receive_event_reply(self, unique_id):
        self.mark_event_as_replied(unique_id)


def setup_socketio(app):
    socketio = SocketIO(app, logger=True, engineio_logger=True, cors_allowed_origins="*")
    CORS(app, resources={r"/*": {"origins": "*"}})

    event_manager = EventManager(socketio)

    @socketio.on('disconnect')
    def user_disconnect():
        user_id = request.sid
        event_manager.game_manager.user_disconnect_handler(user_id)

    @socketio.on('game_mode_selection')
    def game_mode_selection(data):
        user_id = request.sid
        event_manager.game_manager.game_mode_selection_handler(data, user_id)

    @socketio.on('playSameRank')
    def play_same_rank(data):
        user_id = request.sid
        event_manager.game_manager.round_manager.play_same_rank_handler(data, user_id)

    @socketio.on('cardToPlay')
    def card_to_play(data):
        user_id = request.sid
        event_manager.game_manager.round_manager.card_to_play_handler(data, user_id)

    @socketio.on('cardDeckSelected')
    def card_deck_selected(data):
        user_id = request.sid
        event_manager.game_manager.round_manager.card_deck_selected_handler(data, user_id)

    @socketio.on('specialRankPlay')
    def special_rank_play(data):
        user_id = request.sid
        event_manager.game_manager.round_manager.special_rank_play_handler(data, user_id)

    @socketio.on('ending-game')
    def end_game(data):
        event_manager.game_manager.end_game_handler(data)

    @socketio.on('starting-game')
    def start_game(data):
        event_manager.game_manager.start_game_handler(data)

    @socketio.on('playerJoinGame')
    def player_join_game(data):
        user_id = request.sid
        event_manager.game_manager.player_join_game_handler(data, user_id)

    @socketio.on('revealFirstCards')
    def reveal_first_cards(data):
        user_id = request.sid
        event_manager.game_manager.reveal_first_cards_handler(data, user_id)

    @socketio.on('userCalledGame')
    def user_called_game(data):
        user_id = request.sid
        event_manager.game_manager.user_called_game_handler(data, user_id)

    @socketio.on('msgBoardAndAnimReply')
    def msg_board_and_anim_reply(data):
        unique_id = data.get('unique_id')
        if unique_id:
            event_manager.receive_event_reply(unique_id)

    return socketio
