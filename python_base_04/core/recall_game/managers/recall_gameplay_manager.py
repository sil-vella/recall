from typing import Optional, Dict, Any, List
import time
from tools.logger.custom_logging import custom_log


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

            if not game_id:
                game_id = self.game_state_manager.create_game(max_players=4)

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
                game.add_player(player)

            if len(game.players) >= 2 and game.current_player_id is None:
                game.start_game()

            payload = {
                'type': 'recall_event',
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

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            game.remove_player(user_id)

            payload = {
                'type': 'recall_event',
                'event_type': 'player_left',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'player': {'id': user_id, 'name': session_data.get('username') or 'Player'},
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

            event_type = engine_result.get('event_type') or 'game_state_updated'
            payload = {
                'type': 'recall_event',
                'event_type': event_type,
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'result': engine_result,
            }
            self._broadcast_message(game_id, payload, session_id)
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
                'type': 'recall_event',
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
                'type': 'recall_event',
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
                    'type': 'recall_event',
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
                    'type': 'recall_event',
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
                    'type': 'recall_event',
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
                'type': 'recall_event',
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
                for room_id, room_info in all_rooms.items():
                    if room_info.get('permission') == 'public':
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
                            'auto_start': room_info.get('auto_start', True)
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
            self.websocket_manager.broadcast_message(room_id, payload, sender_session_id)
        except Exception as e:
            custom_log(f"Error broadcasting recall event: {e}")

    def _emit_to_session(self, session_id: str, event: str, data: dict):
        if self.websocket_manager:
            self.websocket_manager.send_to_session(session_id, event, data)

    def _emit_error(self, session_id: str, message: str):
        self._emit_to_session(session_id, 'recall_error', {'message': message})

    def _to_flutter_card(self, card) -> Dict[str, Any]:
        suit = card.suit
        rank = card.rank
        return {
            'suit': suit,
            'rank': rank,
            'points': int(card.points),
            'specialPower': (card.special_power or 'none'),
            'specialPowerDescription': None,
            'specialPowerData': None,
            'displayName': str(card),
            'color': 'red' if suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c) for c in player.hand],
            'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
            'score': int(player.calculate_points()),
            'status': 'playing' if is_current else 'ready',
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_phase(self, phase: str) -> str:
        mapping = {
            'waiting_for_players': 'waiting',
            'dealing_cards': 'setup',
            'player_turn': 'playing',
            'out_of_turn_play': 'playing',
            'recall_called': 'recall',
            'game_ended': 'finished',
        }
        return mapping.get(phase, 'waiting')

    def _to_flutter_game_state(self, game) -> Dict[str, Any]:
        players_list: List[Dict[str, Any]] = []
        for pid, p in game.players.items():
            players_list.append(self._to_flutter_player(p, pid == game.current_player_id))

        return {
            'gameId': game.game_id,
            'gameName': f'Recall Game {game.game_id[:6]}',
            'players': players_list,
            'currentPlayer': self._to_flutter_player(game.players[game.current_player_id], True) if game.current_player_id and game.current_player_id in game.players else None,
            'phase': self._to_flutter_phase(game.phase.value),
            'status': 'active' if not game.game_ended else 'ended',
            'drawPile': [],
            'discardPile': [self._to_flutter_card(c) for c in game.discard_pile],
            'centerPile': [],
            'turnNumber': 0,
            'roundNumber': 1,
            'gameStartTime': None,
            'lastActivityTime': None,
            'gameSettings': {},
            'winner': None,
            'errorMessage': None,
            # Extra metadata for UX
            'outOfTurnEndsAt': getattr(game, 'out_of_turn_deadline', None),
        }


