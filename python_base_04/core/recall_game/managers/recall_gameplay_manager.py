from typing import Optional, Dict, Any, List
import time
from datetime import datetime
from tools.logger.custom_logging import custom_log
from ..models.game_state import GameState, Player


class RecallGameplayManager:
    """Encapsulates Recall gameplay WebSocket handlers and mapping helpers.

    This manager integrates with the existing app/websocket managers and
    delegates to the declarative GameState/GameLogicEngine where applicable.
    """

    def __init__(self):
        self.app_manager = None
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_logic_engine = None

    def initialize(self, app_manager, game_state_manager, game_logic_engine) -> bool:
        try:
            self.app_manager = app_manager
            self.websocket_manager = app_manager.get_websocket_manager()
            self.game_state_manager = game_state_manager
            self.game_logic_engine = game_logic_engine
            if not self.websocket_manager:
                custom_log("❌ WebSocket manager not available for Recall gameplay", level="ERROR")
                return False
            return True
        except Exception as e:
            custom_log(f"❌ Failed to initialize RecallGameplayManager: {e}", level="ERROR")
            return False

    # ========= Public listener entry points =========

    def on_get_public_rooms(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            return self._handle_get_public_rooms({'session_id': session_id})
        except Exception as e:
            custom_log(f"Error in on_get_public_rooms: {e}", level="ERROR")
            return False

    def on_join_game(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id')
            player_name = data.get('player_name') or 'Player'
            player_type = data.get('player_type') or 'human'
            max_players = data.get('max_players', 4)  # Get from frontend data, default to 4

            # Align game with room id: if provided id has no game, create one with that id
            if not game_id:
                game_id = self.game_state_manager.create_game(max_players=max_players)
            else:
                game = self.game_state_manager.get_game(game_id)
                if not game:
                    # Use provided id as game id to align with room
                    self.game_state_manager.create_game_with_id(game_id, max_players=max_players)

            game = self.game_state_manager.get_game(game_id)
            if not game:
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False

            self.websocket_manager.join_room(game_id, session_id)

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)

            from ..models.player import HumanPlayer, ComputerPlayer
            if user_id not in game.players:
                player = ComputerPlayer(user_id, player_name) if player_type == 'computer' else HumanPlayer(user_id, player_name)
                # Add player with session tracking
                game.add_player(player, session_id)
                custom_log(f"✅ Added player {user_id} to game {game_id} with session {session_id}")
            else:
                # Update session mapping for existing player
                game.update_player_session(user_id, session_id)
                custom_log(f"✅ Updated session mapping for player {user_id} in game {game_id}")

            # Do not auto-start here; wait for explicit start via recall_start_match

            payload = {
                'event_type': 'game_joined',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'player': self._to_flutter_player(game.players[user_id], user_id == game.current_player_id),
            }
            self._broadcast_message(game_id, payload, session_id)
            return True
        except Exception as e:
            custom_log(f"Error in on_join_game: {e}", level="ERROR")
            self._emit_error(session_id, f'Join game failed: {str(e)}')
            return False

    def on_leave_game(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id')
            if not game_id:
                self._emit_error(session_id, 'Missing game_id')
                return False
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return True

            self.websocket_manager.leave_room(game_id, session_id)

            # Get player_id from session mapping
            player_id = game.get_session_player(session_id)
            if not player_id:
                # Fallback to session data
                session_data = self.websocket_manager.get_session_data(session_id) or {}
                player_id = str(session_data.get('user_id') or session_id)
            
            # Remove player (this also cleans up session mapping)
            game.remove_player(player_id)
            custom_log(f"✅ Removed player {player_id} from game {game_id}")

            payload = {
                'event_type': 'player_left',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'player': {'id': player_id, 'name': session_data.get('username') or 'Player'},
            }
            self._broadcast_message(game_id, payload, session_id)
            return True
        except Exception as e:
            custom_log(f"Error in on_leave_game: {e}", level="ERROR")
            self._emit_error(session_id, f'Leave game failed: {str(e)}')
            return False

    def on_player_action(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id') or data.get('room_id')
            action = data.get('action') or data.get('action_type')
            if not game_id or not action:
                self._emit_error(session_id, 'Missing game_id or action')
                return False
            game = self.game_state_manager.get_game(game_id)
            if not game:
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or data.get('player_id') or session_id)

            # Build action_data for YAML engine
            action_data: Dict[str, Any] = {
                'action_type': action,
                'player_id': user_id,
                'game_id': game_id,
                'card_id': (data.get('card') or {}).get('card_id') or (data.get('card') or {}).get('id'),
                'replace_card_id': (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id'),
                'replace_index': data.get('replaceIndex'),
                'power_data': data.get('power_data'),
            }

            # Engine processes action via YAML rules
            engine_result = self.game_logic_engine.process_player_action(game, action_data)

            # Fallback for actions not yet in YAML: minimal delegations
            if not engine_result or engine_result.get('error'):
                engine_result = self._fallback_handle(game, action, user_id, data)

            # Handle action result with individual messaging
            if engine_result.get('error'):
                # Send error to the player who performed the action
                self.send_game_action_result(game_id, user_id, engine_result)
                return False
            
            # Send action result to the player who performed it
            self.send_game_action_result(game_id, user_id, engine_result)
            
            # Broadcast game action to other players
            action_broadcast_data = {
                'action_type': action,
                'player_id': user_id,
                'result': engine_result,
            }
            self.broadcast_game_action(game_id, action, action_broadcast_data, user_id)
            
            # Send private hand update to the player who performed the action
            self.send_private_hand_update(game_id, user_id)
            
            # Handle turn changes
            if engine_result.get('next_player'):
                next_player_id = engine_result.get('next_player')
                if next_player_id and next_player_id in game.players:
                    self.send_turn_notification(game_id, next_player_id)
            
            # Handle game state updates for all players
            game_state_payload = {
                'event_type': 'game_state_updated',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
            }
            self.send_to_all_players(game_id, 'game_state_updated', game_state_payload)
            
            # Check if next player is a computer and trigger their turn
            if engine_result.get('next_player'):
                next_player_id = engine_result.get('next_player')
                if next_player_id and next_player_id in game.players:
                    next_player = game.players[next_player_id]
                    if next_player.player_type.value == 'computer':
                        # Add a small delay to make the game feel more natural
                        import threading
                        
                        def delayed_computer_turn():
                            import time
                            time.sleep(1)  # 1 second delay
                            self.trigger_computer_turn(game_id, next_player_id)
                        
                        # Run in background thread
                        thread = threading.Thread(target=delayed_computer_turn)
                        thread.daemon = True
                        thread.start()
            
            # Check for computer out-of-turn opportunities
            if engine_result.get('success') and action in ['play_card', 'play_out_of_turn']:
                # Add a small delay to let the card play settle
                import threading
                
                def delayed_out_of_turn_check():
                    import time
                    time.sleep(0.5)  # 0.5 second delay
                    self.check_computer_out_of_turn_opportunities(game_id)
                
                # Run in background thread
                thread = threading.Thread(target=delayed_out_of_turn_check)
                thread.daemon = True
                thread.start()
            
            return True
        except Exception as e:
            custom_log(f"Error in on_player_action: {e}", level="ERROR")
            self._emit_error(session_id, f'Player action failed: {str(e)}')
            return False

    def _fallback_handle(self, game, action: str, user_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        # Minimal compatibility with current GameState methods while YAML rules expand
        if action == 'draw_from_deck':
            return game.draw_from_deck(user_id)
        if action == 'take_from_discard':
            return game.take_from_discard(user_id)
        if action in ('place_drawn_replace', 'place_drawn_card_replace'):
            replace_id = (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id')
            replace_index = data.get('replaceIndex')
            if not replace_id and replace_index is not None and user_id in game.players:
                try:
                    idx = int(replace_index)
                    hand = game.players[user_id].hand
                    if 0 <= idx < len(hand):
                        replace_id = hand[idx].card_id
                except Exception:
                    replace_id = None
            if not replace_id:
                return {'error': 'Missing replace target (id or index)'}
            return game.place_drawn_card_replace(user_id, replace_id)
        if action in ('place_drawn_play', 'place_drawn_card_play'):
            return game.place_drawn_card_play(user_id)
        if action == 'play_card':
            card = data.get('card') or {}
            cid = card.get('card_id') or card.get('id')
            if not cid:
                return {'error': 'Missing card_id'}
            return game.play_card(user_id, cid)
        if action == 'play_out_of_turn':
            card = data.get('card') or {}
            cid = card.get('card_id') or card.get('id')
            if not cid:
                return {'error': 'Missing card_id'}
            return game.play_out_of_turn(user_id, cid)
        if action == 'call_recall':
            return game.call_recall(user_id)
        if action == 'use_special_power':
            return {'success': True, 'power_used': data.get('power_data')}
        return {'error': 'Unsupported action'}

    def on_call_recall(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id')
            if not game_id:
                self._emit_error(session_id, 'Missing game_id')
                return False
            game = self.game_state_manager.get_game(game_id)
            if not game:
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            result = game.call_recall(user_id)

            payload = {
                'event_type': 'recall_called',
                'game_id': game_id,
                'updated_game_state': self._to_flutter_game_state(game),
                'result': result,
            }
            self._broadcast_message(game_id, payload, session_id)
            return True
        except Exception as e:
            custom_log(f"Error in on_call_recall: {e}", level="ERROR")
            self._emit_error(session_id, f'Call recall failed: {str(e)}')
            return False

    def on_play_out_of_turn(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id')
            card = data.get('card') or {}
            cid = card.get('card_id') or card.get('id')
            if not game_id or not cid:
                self._emit_error(session_id, 'Missing game_id or card_id')
                return False
            game = self.game_state_manager.get_game(game_id)
            if not game:
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            result = game.play_out_of_turn(user_id, cid)

            payload = {
                'event_type': 'card_played',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'result': result,
            }
            self._broadcast_message(game_id, payload, session_id)
            return True
        except Exception as e:
            custom_log(f"Error in on_play_out_of_turn: {e}", level="ERROR")
            self._emit_error(session_id, f'Out-of-turn play failed: {str(e)}')
            return False

    def on_use_special_power(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id')
            if not game_id:
                self._emit_error(session_id, 'Missing game_id')
                return False
            game = self.game_state_manager.get_game(game_id)
            if not game:
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            power = (data.get('power_data') or {}).get('power')
            if power == 'peek_at_card':
                target_player_id = data['power_data'].get('target_player_id')
                target_card_index = data['power_data'].get('target_card_index')
                player = game.players.get(target_player_id)
                if player is None:
                    self._emit_error(session_id, 'Invalid target player')
                    return False
                card = player.look_at_card_by_index(int(target_card_index))
                if card is None:
                    self._emit_error(session_id, 'Invalid target card index')
                    return False
                payload = {
                    'event_type': 'special_power_used',
                    'game_id': game_id,
                    'game_state': self._to_flutter_game_state(game),
                    'result': {
                        'success': True,
                        'power': 'peek_at_card',
                        'target_player_id': target_player_id,
                        'target_card_index': target_card_index,
                    }
                }
                self._broadcast_message(game_id, payload, session_id)
                return True
            elif power == 'switch_cards':
                src_pid = data['power_data'].get('source_player_id')
                dst_pid = data['power_data'].get('dest_player_id')
                src_idx = int(data['power_data'].get('source_card_index'))
                dst_idx = int(data['power_data'].get('dest_card_index'))
                src = game.players.get(src_pid)
                dst = game.players.get(dst_pid)
                if not src or not dst:
                    self._emit_error(session_id, 'Invalid players for switch')
                    return False
                if src_idx < 0 or src_idx >= len(src.hand) or dst_idx < 0 or dst_idx >= len(dst.hand):
                    self._emit_error(session_id, 'Invalid card indices for switch')
                    return False
                src_card = src.hand[src_idx]
                dst_card = dst.hand[dst_idx]
                src.hand[src_idx], dst.hand[dst_idx] = dst_card, src_card
                payload = {
                    'event_type': 'special_power_used',
                    'game_id': game_id,
                    'game_state': self._to_flutter_game_state(game),
                    'result': {
                        'success': True,
                        'power': 'switch_cards',
                        'source_player_id': src_pid,
                        'source_card_index': src_idx,
                        'dest_player_id': dst_pid,
                        'dest_card_index': dst_idx,
                    }
                }
                self._broadcast_message(game_id, payload, session_id)
                return True
            else:
                payload = {
                    'event_type': 'special_power_used',
                    'game_id': game_id,
                    'game_state': self._to_flutter_game_state(game),
                    'result': {'success': True, 'power': power}
                }
                self._broadcast_message(game_id, payload, session_id)
                return True
        except Exception as e:
            custom_log(f"Error in on_use_special_power: {e}", level="ERROR")
            self._emit_error(session_id, f'Use special power failed: {str(e)}')
            return False

    def on_start_match(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Explicit match start: initialize deck (deterministic), deal, first player."""
        try:
            custom_log(f"🎮 [on_start_match] Starting with session_id: {session_id}, data: {data}")
            
            game_id = data.get('game_id') or data.get('room_id')
            custom_log(f"🎮 [on_start_match] Extracted game_id: {game_id}")
            
            if not game_id:
                custom_log(f"❌ [on_start_match] Missing game_id in data: {data}")
                self._emit_error(session_id, 'Missing game_id')
                return False
                
            game = self.game_state_manager.get_game(game_id)
            custom_log(f"🎮 [on_start_match] Retrieved game: {game is not None}")
            
            if not game:
                custom_log(f"❌ [on_start_match] Game not found: {game_id}")
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False

            # If already started, avoid re-dealing. Just echo current state.
            try:
                from ..models.game_state import GamePhase
                custom_log(f"🎮 [on_start_match] Game phase: {game.phase}")
                if game.phase != GamePhase.WAITING_FOR_PLAYERS:
                    custom_log(f"🎮 [on_start_match] Game already started, echoing current state")
                    payload = {
                        'event_type': 'game_state_updated',
                        'game_id': game_id,
                        'game_state': self._to_flutter_game_state(game),
                    }
                    self._broadcast_message(game_id, payload, session_id)
                    return True
            except Exception as e:
                custom_log(f"⚠️ [on_start_match] Error checking game phase: {e}")

            # Computer player addition is now handled by the game engine

            # Use game engine to process start_match action
            custom_log(f"🎮 [on_start_match] Processing start_match via game engine...")
            
            # Get user_id from session data
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            custom_log(f"🎮 [on_start_match] Using user_id: {user_id}")
            
            # Build action data for YAML engine
            action_data = {
                'action_type': 'start_match',
                'player_id': user_id,
                'game_id': game_id,
            }
            
            # Process action through game engine
            engine_result = self.game_logic_engine.process_player_action(game, action_data)
            custom_log(f"🎮 [on_start_match] Game engine result: {engine_result}")
            
            if engine_result.get('error'):
                custom_log(f"❌ [on_start_match] Game engine error: {engine_result['error']}")
                self._emit_error(session_id, f"Start match failed: {engine_result['error']}")
                return False
            
            # Process notifications from the engine
            notifications = engine_result.get('notifications', [])
            for notification in notifications:
                event = notification.get('event')
                data = notification.get('data', {})
                
                if event == 'game_started':
                    # Send game started event to all players individually
                    payload = {
                        'event_type': event,
                        'game_id': game_id,
                        'game_state': self._to_flutter_game_state(game),
                        **data  # Include additional data from engine
                    }
                    custom_log(f"🎮 [on_start_match] Broadcasting {event} event to all players")
                    custom_log(f"🎮 [on_start_match] Payload: {payload}")
                    self.send_to_all_players(game_id, event, payload)
                elif event == 'game_phase_changed':
                    # Send phase change event to all players
                    payload = {
                        'event_type': event,
                        'game_id': game_id,
                        **data
                    }
                    custom_log(f"🎮 [on_start_match] Broadcasting {event} event to all players")
                    self.send_to_all_players(game_id, event, payload)
                elif event == 'turn_started':
                    # Send turn notification to specific player
                    target_player_id = data.get('player_id')
                    if target_player_id:
                        payload = {
                            'event_type': event,
                            'game_id': game_id,
                            'game_state': self._to_flutter_game_state(game),
                            **data
                        }
                        custom_log(f"🎮 [on_start_match] Sending {event} to player {target_player_id}")
                        self.send_to_player(game_id, target_player_id, event, payload)
                else:
                    # Default: broadcast to all players
                    payload = {
                        'event_type': event,
                        'game_id': game_id,
                        **data
                    }
                    custom_log(f"🎮 [on_start_match] Broadcasting {event} event to all players")
                    self.send_to_all_players(game_id, event, payload)
            
            custom_log(f"🎮 [on_start_match] Successfully completed via game engine")
            
            # Check if first player is a computer and trigger their turn
            if game.current_player_id:
                current_player = game.players.get(game.current_player_id)
                if current_player and current_player.player_type.value == 'computer':
                    custom_log(f"🤖 [on_start_match] First player is computer, triggering turn: {game.current_player_id}")
                    # Add a small delay to let the game start event settle
                    import threading
                    
                    def delayed_computer_turn():
                        import time
                        time.sleep(3)  # 3 second delay for game start
                        self.trigger_computer_turn(game_id, game.current_player_id)
                    
                    # Run in background thread
                    thread = threading.Thread(target=delayed_computer_turn)
                    thread.daemon = True
                    thread.start()
            
            return True
        except Exception as e:
            custom_log(f"❌ [on_start_match] Error in on_start_match: {e}", level="ERROR")
            self._emit_error(session_id, f'Start match failed: {str(e)}')
            return False

    def on_session_disconnect(self, session_id: str) -> bool:
        """Handle session disconnection and cleanup"""
        try:
            custom_log(f"🔌 [on_session_disconnect] Session disconnected: {session_id}")
            
            # Find all games this session is part of
            if not self.game_state_manager:
                return False
            
            disconnected_players = []
            
            # Check all active games for this session
            for game_id in self.game_state_manager.active_games:
                game = self.game_state_manager.get_game(game_id)
                if game:
                    player_id = game.get_session_player(session_id)
                    if player_id:
                        disconnected_players.append((game_id, player_id))
                        custom_log(f"🔌 [on_session_disconnect] Found player {player_id} in game {game_id}")
            
            # Handle disconnections
            for game_id, player_id in disconnected_players:
                game = self.game_state_manager.get_game(game_id)
                if game:
                    # Remove session mapping but keep player in game (they can reconnect)
                    game.remove_session(session_id)
                    custom_log(f"🔌 [on_session_disconnect] Removed session mapping for player {player_id} in game {game_id}")
                    
                    # Notify other players about the disconnection
                    disconnect_payload = {
                        'event_type': 'player_disconnected',
                        'game_id': game_id,
                        'player_id': player_id,
                        'game_state': self._to_flutter_game_state(game),
                    }
                    self.send_to_other_players(game_id, player_id, 'player_disconnected', disconnect_payload)
            
            return True
        except Exception as e:
            custom_log(f"❌ [on_session_disconnect] Error handling disconnect: {e}", level="ERROR")
            return False

    def on_session_reconnect(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle session reconnection"""
        try:
            game_id = data.get('game_id')
            if not game_id:
                return False
            
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return False
            
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            
            # Check if player exists in game
            if user_id in game.players:
                # Update session mapping
                game.update_player_session(user_id, session_id)
                custom_log(f"🔌 [on_session_reconnect] Reconnected player {user_id} in game {game_id}")
                
                # Notify other players about the reconnection
                reconnect_payload = {
                    'event_type': 'player_reconnected',
                    'game_id': game_id,
                    'player_id': user_id,
                    'game_state': self._to_flutter_game_state(game),
                }
                self.send_to_other_players(game_id, user_id, 'player_reconnected', reconnect_payload)
                
                # Send current game state to reconnected player
                current_state_payload = {
                    'event_type': 'game_state_updated',
                    'game_id': game_id,
                    'game_state': self._to_flutter_game_state(game),
                }
                self._emit_to_session(session_id, 'game_state_updated', current_state_payload)
                
                return True
            
            return False
        except Exception as e:
            custom_log(f"❌ [on_session_reconnect] Error handling reconnect: {e}", level="ERROR")
            return False

    def on_initial_peek(self, session_id: str, data: Dict[str, Any]) -> bool:
        try:
            game_id = data.get('game_id')
            indices = data.get('indices') or []
            if not game_id:
                self._emit_error(session_id, 'Missing game_id')
                return False
            game = self.game_state_manager.get_game(game_id)
            if not game:
                self._emit_error(session_id, f'Game not found: {game_id}')
                return False
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            result = game.initial_peek(user_id, indices)
            payload = {
                'event_type': 'game_state_updated',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'result': result,
            }
            self._broadcast_message(game_id, payload, session_id)
            return True
        except Exception as e:
            custom_log(f"Error in on_initial_peek: {e}", level="ERROR")
            self._emit_error(session_id, f'Initial peek failed: {str(e)}')
            return False

    # ========= Testing and Debugging Helpers =========
    
    def test_session_tracking(self, game_id: str) -> Dict[str, Any]:
        """Test method to verify session tracking is working correctly"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return {'error': 'Game not found'}
            
            tracking_info = {
                'game_id': game_id,
                'player_count': len(game.players),
                'session_count': len(game.player_sessions),
                'players': {},
                'sessions': {},
            }
            
            # Show player -> session mapping
            for player_id, session_id in game.player_sessions.items():
                tracking_info['players'][player_id] = {
                    'session_id': session_id,
                    'player_name': game.players[player_id].name if player_id in game.players else 'Unknown',
                    'player_type': game.players[player_id].player_type.value if player_id in game.players else 'Unknown',
                }
            
            # Show session -> player mapping
            for session_id, player_id in game.session_players.items():
                tracking_info['sessions'][session_id] = {
                    'player_id': player_id,
                    'player_name': game.players[player_id].name if player_id in game.players else 'Unknown',
                }
            
            custom_log(f"🔍 [test_session_tracking] Session tracking info: {tracking_info}")
            return tracking_info
            
        except Exception as e:
            custom_log(f"❌ [test_session_tracking] Error: {e}", level="ERROR")
            return {'error': str(e)}
    
    def get_game_session_info(self, game_id: str) -> Dict[str, Any]:
        """Get comprehensive session information for a game"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return {'error': 'Game not found'}
            
            session_info = {
                'game_id': game_id,
                'phase': game.phase.value,
                'current_player_id': game.current_player_id,
                'connected_players': [],
                'disconnected_players': [],
            }
            
            # Check each player's connection status
            for player_id, player in game.players.items():
                session_id = game.get_player_session(player_id)
                if session_id:
                    session_info['connected_players'].append({
                        'player_id': player_id,
                        'player_name': player.name,
                        'session_id': session_id,
                        'player_type': player.player_type.value,
                    })
                else:
                    session_info['disconnected_players'].append({
                        'player_id': player_id,
                        'player_name': player.name,
                        'player_type': player.player_type.value,
                    })
            
            return session_info
            
        except Exception as e:
            custom_log(f"❌ [get_game_session_info] Error: {e}", level="ERROR")
            return {'error': str(e)}

    def test_computer_player_system(self, game_id: str) -> Dict[str, Any]:
        """Test method to verify computer player system is working correctly"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return {'error': 'Game not found'}
            
            computer_info = {
                'game_id': game_id,
                'current_player_id': game.current_player_id,
                'current_player_type': None,
                'computer_players': [],
                'human_players': [],
                'can_trigger_computer_turn': False,
            }
            
            # Get current player info
            if game.current_player_id:
                current_player = game.players.get(game.current_player_id)
                if current_player:
                    computer_info['current_player_type'] = current_player.player_type.value
                    computer_info['can_trigger_computer_turn'] = current_player.player_type.value == 'computer'
            
            # Categorize players
            for player_id, player in game.players.items():
                player_info = {
                    'player_id': player_id,
                    'player_name': player.name,
                    'player_type': player.player_type.value,
                    'hand_size': len(player.hand),
                    'score': player.calculate_points(),
                }
                
                if player.player_type.value == 'computer':
                    computer_info['computer_players'].append(player_info)
                else:
                    computer_info['human_players'].append(player_info)
            
            # Test computer turn triggering
            if computer_info['can_trigger_computer_turn']:
                computer_info['test_result'] = 'Computer turn can be triggered'
                # Uncomment the next line to actually test the computer turn
                # self.trigger_computer_turn(game_id, game.current_player_id)
            else:
                computer_info['test_result'] = 'Current player is not a computer'
            
            custom_log(f"🤖 [test_computer_player_system] Computer player info: {computer_info}")
            return computer_info
            
        except Exception as e:
            custom_log(f"❌ [test_computer_player_system] Error: {e}", level="ERROR")
            return {'error': str(e)}

    # ========= Internal helpers =========

    def _handle_get_public_rooms(self, data: Dict[str, Any]) -> bool:
        try:
            session_id = data.get('session_id')
            if not session_id:
                self._emit_error(session_id, 'Session ID required')
                return False

            if self.websocket_manager and hasattr(self.websocket_manager, 'room_manager'):
                all_rooms = self.websocket_manager.room_manager.get_all_rooms()
                public_rooms = []
                # all_rooms is a List[Dict], not a Dict, so iterate directly
                for room_info in all_rooms:
                    if room_info.get('permission') == 'public':
                        room_id = room_info.get('room_id', 'unknown')
                        
                        # Include game status information
                        game_id = room_id  # Game ID same as room ID
                        has_game = game_id in self.game_state_manager.active_games if self.game_state_manager else False
                        game_phase = None
                        game_status = None
                        
                        if has_game and self.game_state_manager:
                            game = self.game_state_manager.get_game(game_id)
                            if game:
                                game_phase = game.phase
                                game_status = game.status
                        
                        public_rooms.append({
                            'room_id': room_id,
                            'room_name': room_info.get('room_name', room_id),
                            'owner_id': room_info.get('owner_id'),
                            'permission': room_info.get('permission'),
                            'current_size': room_info.get('current_size', 0),
                            'max_size': room_info.get('max_size', 4),
                            'min_size': room_info.get('min_size', 2),
                            'created_at': room_info.get('created_at'),
                            'game_type': room_info.get('game_type', 'classic'),
                            'turn_time_limit': room_info.get('turn_time_limit', 30),
                            'auto_start': room_info.get('auto_start', True),
                            'has_game': has_game,
                            'game_phase': game_phase,
                            'game_status': game_status,
                        })
                self._emit_to_session(session_id, 'get_public_rooms_success', {
                    'success': True,
                    'data': public_rooms,
                    'count': len(public_rooms),
                    'timestamp': time.time()
                })
                return True
            else:
                self._emit_to_session(session_id, 'get_public_rooms_success', {
                    'success': True,
                    'data': [],
                    'count': 0,
                    'timestamp': time.time()
                })
                return True
        except Exception as e:
            custom_log(f"Error in _handle_get_public_rooms: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error getting public rooms: {str(e)}')
            return False

    def _broadcast_message(self, room_id: str, payload: Dict[str, Any], sender_session_id: Optional[str] = None):
        try:
            # Broadcast individual events instead of grouped recall_game_event
            event_type = payload.get('event_type')
            if event_type:
                # Remove event_type from payload since it becomes the event name
                event_payload = {k: v for k, v in payload.items() if k != 'event_type'}
                self.websocket_manager.socketio.emit(event_type, event_payload, room=room_id)
                custom_log(f"✅ Broadcasted {event_type} to room {room_id}")
            else:
                custom_log(f"❌ No event_type found in payload: {payload}")
        except Exception as e:
            custom_log(f"❌ Error broadcasting event: {e}")

    def _emit_to_session(self, session_id: str, event: str, data: dict):
        if self.websocket_manager:
            self.websocket_manager.send_to_session(session_id, event, data)

    def _emit_error(self, session_id: str, message: str):
        self._emit_to_session(session_id, 'recall_error', {'message': message})

    # ========= Individual Player Messaging Helpers =========
    
    def send_to_player(self, game_id: str, player_id: str, event: str, data: dict) -> bool:
        """Send event to a specific player"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"❌ Game not found for player messaging: {game_id}", level="ERROR")
                return False
            
            session_id = game.get_player_session(player_id)
            if not session_id:
                custom_log(f"❌ No session found for player: {player_id}", level="ERROR")
                return False
            
            self._emit_to_session(session_id, event, data)
            custom_log(f"✅ Sent {event} to player {player_id} (session: {session_id})")
            return True
        except Exception as e:
            custom_log(f"❌ Error sending to player {player_id}: {e}", level="ERROR")
            return False
    
    def send_to_all_players(self, game_id: str, event: str, data: dict, exclude_player_id: str = None) -> bool:
        """Send event to all players in a game, optionally excluding one"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"❌ Game not found for broadcast: {game_id}", level="ERROR")
                return False
            
            sent_count = 0
            for player_id, session_id in game.player_sessions.items():
                if exclude_player_id and player_id == exclude_player_id:
                    continue
                
                self._emit_to_session(session_id, event, data)
                sent_count += 1
            
            custom_log(f"✅ Sent {event} to {sent_count} players in game {game_id}")
            return sent_count > 0
        except Exception as e:
            custom_log(f"❌ Error broadcasting to players: {e}", level="ERROR")
            return False
    
    def send_to_other_players(self, game_id: str, exclude_player_id: str, event: str, data: dict) -> bool:
        """Send event to all players except the specified one"""
        return self.send_to_all_players(game_id, event, data, exclude_player_id)
    
    def get_player_session(self, game_id: str, player_id: str) -> Optional[str]:
        """Get session ID for a player in a game"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if game:
                return game.get_player_session(player_id)
        except Exception as e:
            custom_log(f"❌ Error getting player session: {e}", level="ERROR")
        return None
    
    def get_session_player(self, game_id: str, session_id: str) -> Optional[str]:
        """Get player ID for a session in a game"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if game:
                return game.get_session_player(session_id)
        except Exception as e:
            custom_log(f"❌ Error getting session player: {e}", level="ERROR")
        return None

    # ========= Player-Specific Event Helpers =========
    
    def send_private_hand_update(self, game_id: str, player_id: str) -> bool:
        """Send private hand update to a specific player"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game or player_id not in game.players:
                return False
            
            player = game.players[player_id]
            
            # Create private hand data (only visible cards for other players)
            private_hand_data = {
                'event_type': 'private_hand_update',
                'game_id': game_id,
                'player_id': player_id,
                'hand': [self._to_flutter_card(card) for card in player.hand],
                'visible_cards': [self._to_flutter_card(card) for card in player.visible_cards],
                'score': int(player.calculate_points()),
            }
            
            return self.send_to_player(game_id, player_id, 'private_hand_update', private_hand_data)
        except Exception as e:
            custom_log(f"❌ Error sending private hand update: {e}", level="ERROR")
            return False
    
    def send_turn_notification(self, game_id: str, player_id: str) -> bool:
        """Send turn notification to a specific player"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game or player_id not in game.players:
                return False
            
            turn_data = {
                'event_type': 'turn_started',
                'game_id': game_id,
                'player_id': player_id,
                'game_state': self._to_flutter_game_state(game),
                'timeout_seconds': game.out_of_turn_timeout_seconds if game.out_of_turn_deadline else None,
            }
            
            return self.send_to_player(game_id, player_id, 'turn_started', turn_data)
        except Exception as e:
            custom_log(f"❌ Error sending turn notification: {e}", level="ERROR")
            return False
    
    def send_game_action_result(self, game_id: str, player_id: str, action_result: Dict[str, Any]) -> bool:
        """Send action result to the player who performed the action"""
        try:
            result_data = {
                'event_type': 'action_result',
                'game_id': game_id,
                'action_result': action_result,
            }
            
            return self.send_to_player(game_id, player_id, 'action_result', result_data)
        except Exception as e:
            custom_log(f"❌ Error sending action result: {e}", level="ERROR")
            return False
    
    def broadcast_game_action(self, game_id: str, action_type: str, action_data: Dict[str, Any], exclude_player_id: str = None) -> bool:
        """Broadcast game action to all players except the one who performed it"""
        try:
            broadcast_data = {
                'event_type': 'game_action',
                'game_id': game_id,
                'action_type': action_type,
                'action_data': action_data,
                'game_state': self._to_flutter_game_state(self.game_state_manager.get_game(game_id)),
            }
            
            return self.send_to_other_players(game_id, exclude_player_id, 'game_action', broadcast_data)
        except Exception as e:
            custom_log(f"❌ Error broadcasting game action: {e}", level="ERROR")
            return False

    def _to_flutter_card(self, card) -> Dict[str, Any]:
        suit = card.suit
        rank = card.rank
        return {
            'suit': suit,
            'rank': rank,
            'points': card.points,
            'displayName': str(card),  # Use __str__ method instead of display_name attribute
            'color': 'red' if suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c) for c in player.hand],
            'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
            'score': int(player.calculate_points()),  # Use calculate_points() method
            'status': 'playing' if is_current else 'ready',
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_game_state(self, game: GameState) -> Dict[str, Any]:
        """Convert backend game state to Flutter format"""
        
        # Map backend phases to Flutter phases
        def _to_flutter_phase(phase: str) -> str:
            mapping = {
                'waiting_for_players': 'waiting',
                'dealing_cards': 'setup',
                'player_turn': 'playing',
                'out_of_turn_play': 'playing',
                'recall_called': 'recall',
                'game_ended': 'finished',
            }
            return mapping.get(phase, 'waiting')
        
        # Convert players to frontend format
        def _to_flutter_player(player_id: str, player: Player) -> Dict[str, Any]:
            return {
                'id': player_id,
                'name': player.name,
                'type': 'human' if player.player_type.value == 'human' else 'computer',
                'hand': [self._to_flutter_card(card) for card in player.hand],
                'visibleCards': [self._to_flutter_card(card) for card in player.visible_cards],
                'score': int(player.calculate_points()),  # Use calculate_points() method
                'status': 'ready' if player.is_active else 'disconnected',
                'isCurrentPlayer': player_id == game.current_player_id,
                'hasCalledRecall': bool(player.has_called_recall),
                'lastActivity': None,  # TODO: Track this
                'handPoints': sum(card.points for card in player.hand),
                'visiblePoints': sum(card.points for card in player.visible_cards),
                'totalScore': int(player.calculate_points()),  # Use calculate_points() method
                'handSize': len(player.hand),
                'visibleSize': len(player.visible_cards),
            }
        
        # Get current player data
        current_player = None
        if game.current_player_id and game.current_player_id in game.players:
            current_player = _to_flutter_player(
                game.current_player_id, 
                game.players[game.current_player_id]
            )
        
        return {
            'gameId': game.game_id,
            'gameName': f"Recall Game {game.game_id}",
            'players': [_to_flutter_player(pid, player) for pid, player in game.players.items()],
            'currentPlayer': current_player,
            'phase': _to_flutter_phase(game.phase.value),
            'status': 'active' if game.phase.value in ['player_turn', 'out_of_turn_play', 'recall_called'] else 'inactive' if game.phase.value == 'waiting_for_players' else 'ended',
            'drawPile': [self._to_flutter_card(card) for card in game.draw_pile],
            'discardPile': [self._to_flutter_card(card) for card in game.discard_pile],
            'centerPile': [],  # TODO: Implement if needed
            'turnNumber': 0,  # TODO: Track this
            'roundNumber': 1,  # TODO: Track this
                            'gameStartTime': datetime.fromtimestamp(game.game_start_time).isoformat() if game.game_start_time else None,
                'lastActivityTime': datetime.fromtimestamp(game.last_action_time).isoformat() if game.last_action_time else None,
            'gameSettings': {},
            'winner': game.winner,
            'errorMessage': None,
            'playerCount': len(game.players),
            'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
            'gameDuration': 'N/A',  # TODO: Calculate this
        }

    # ========= Computer Player Turn Management =========
    
    def trigger_computer_turn(self, game_id: str, computer_player_id: str) -> bool:
        """Trigger automatic turn for a computer player"""
        try:
            custom_log(f"🤖 [trigger_computer_turn] Triggering turn for computer player: {computer_player_id}")
            
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"❌ [trigger_computer_turn] Game not found: {game_id}", level="ERROR")
                return False
            
            computer_player = game.players.get(computer_player_id)
            if not computer_player or computer_player.player_type.value != 'computer':
                custom_log(f"❌ [trigger_computer_turn] Not a computer player: {computer_player_id}", level="ERROR")
                return False
            
            # Make AI decision
            game_state_dict = game.to_dict()
            ai_decision = computer_player.make_decision(game_state_dict)
            
            custom_log(f"🤖 [trigger_computer_turn] AI decision: {ai_decision}")
            
            # Execute the AI decision
            if ai_decision.get('action'):
                action_data = {
                    'action_type': ai_decision['action'],
                    'player_id': computer_player_id,
                    'game_id': game_id,
                    'card_id': ai_decision.get('card_id'),
                    'replace_card_id': ai_decision.get('replace_card_id'),
                    'replace_index': ai_decision.get('replace_index'),
                    'power_data': ai_decision.get('power_data'),
                }
                
                # Process through game engine
                engine_result = self.game_logic_engine.process_player_action(game, action_data)
                
                if engine_result.get('error'):
                    custom_log(f"❌ [trigger_computer_turn] AI action failed: {engine_result['error']}", level="ERROR")
                    return False
                
                # Handle the result using the same logic as human players
                self._handle_computer_action_result(game_id, computer_player_id, engine_result, ai_decision['action'])
                
                return True
            else:
                custom_log(f"❌ [trigger_computer_turn] No action in AI decision", level="ERROR")
                return False
                
        except Exception as e:
            custom_log(f"❌ [trigger_computer_turn] Error: {e}", level="ERROR")
            return False
    
    def _handle_computer_action_result(self, game_id: str, computer_player_id: str, engine_result: Dict[str, Any], action: str) -> None:
        """Handle the result of a computer player's action"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return
            
            # Send action result to the computer player (for logging/debugging)
            self.send_game_action_result(game_id, computer_player_id, engine_result)
            
            # Broadcast game action to other players
            action_broadcast_data = {
                'action_type': action,
                'player_id': computer_player_id,
                'result': engine_result,
                'is_computer_player': True,
            }
            self.broadcast_game_action(game_id, action, action_broadcast_data, computer_player_id)
            
            # Send private hand update to the computer player
            self.send_private_hand_update(game_id, computer_player_id)
            
            # Handle turn changes
            if engine_result.get('next_player'):
                next_player_id = engine_result.get('next_player')
                if next_player_id and next_player_id in game.players:
                    next_player = game.players[next_player_id]
                    
                    # If next player is also a computer, trigger their turn
                    if next_player.player_type.value == 'computer':
                        # Add a small delay to make the game feel more natural
                        import asyncio
                        import threading
                        
                        def delayed_computer_turn():
                            import time
                            time.sleep(2)  # 2 second delay
                            self.trigger_computer_turn(game_id, next_player_id)
                        
                        # Run in background thread
                        thread = threading.Thread(target=delayed_computer_turn)
                        thread.daemon = True
                        thread.start()
                    else:
                        # Send turn notification to human player
                        self.send_turn_notification(game_id, next_player_id)
            
            # Handle game state updates for all players
            game_state_payload = {
                'event_type': 'game_state_updated',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
            }
            self.send_to_all_players(game_id, 'game_state_updated', game_state_payload)
            
        except Exception as e:
            custom_log(f"❌ [_handle_computer_action_result] Error: {e}", level="ERROR")
    
    def check_and_trigger_computer_turn(self, game_id: str) -> bool:
        """Check if current player is a computer and trigger their turn if needed"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game or not game.current_player_id:
                return False
            
            current_player = game.players.get(game.current_player_id)
            if not current_player:
                return False
            
            # Check if current player is a computer
            if current_player.player_type.value == 'computer':
                custom_log(f"🤖 [check_and_trigger_computer_turn] Current player is computer: {game.current_player_id}")
                return self.trigger_computer_turn(game_id, game.current_player_id)
            
            return False
            
        except Exception as e:
            custom_log(f"❌ [check_and_trigger_computer_turn] Error: {e}", level="ERROR")
            return False

    def check_computer_out_of_turn_opportunities(self, game_id: str) -> bool:
        """Check if any computer players can play out of turn"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game or not game.last_played_card:
                return False
            
            triggered_any = False
            
            # Check all computer players for out-of-turn opportunities
            for player_id, player in game.players.items():
                if (player.player_type.value == 'computer' and 
                    player_id != game.current_player_id and
                    player.can_play_out_of_turn(game.last_played_card)):
                    
                    custom_log(f"🤖 [check_computer_out_of_turn_opportunities] Computer {player_id} can play out of turn")
                    
                    # Add a small delay to make it feel more natural
                    import threading
                    
                    def delayed_out_of_turn():
                        import time
                        time.sleep(1.5)  # 1.5 second delay
                        self.trigger_computer_turn(game_id, player_id)
                    
                    # Run in background thread
                    thread = threading.Thread(target=delayed_out_of_turn)
                    thread.daemon = True
                    thread.start()
                    
                    triggered_any = True
            
            return triggered_any
            
        except Exception as e:
            custom_log(f"❌ [check_computer_out_of_turn_opportunities] Error: {e}", level="ERROR")
            return False


