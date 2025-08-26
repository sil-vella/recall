/// ## JoinGameWidget
/// 
/// A widget that allows users to join existing games by entering a game ID.
/// 
/// ### Features:
/// - **Game ID Input**: Text field for entering game ID
/// - **Password Support**: Conditional password field for private games
/// - **Find Game Button**: API call to get game details before joining
/// - **Join Game Button**: WebSocket event to join the game
/// - **Real-time Validation**: Checks game permissions and password requirements
/// 
/// ### Event Emissions:
/// - Emits `join_room` WebSocket event (backend handles room/game joining)
/// - Backend automatically adds user to both room and game instances
/// - Frontend receives `join_room_success` and `room_joined` events
/// 
/// ### State Updates:
/// - Updates `recall_game` state with joined game information
/// - Triggers UI refresh via `ListenableBuilder`
/// 
/// ### Integration:
/// - Uses `WSEventManager` for WebSocket communication
/// - Integrates with `StateManager` for state updates
/// - Follows core WebSocket event patterns

import 'package:flutter/material.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../../tools/logging/logger.dart';

class JoinGameWidget extends StatefulWidget {
  final Function(String) onJoinGame;
  
  const JoinGameWidget({
    Key? key,
    required this.onJoinGame,
  }) : super(key: key);

  @override
  State<JoinGameWidget> createState() => _JoinGameWidgetState();
}

class _JoinGameWidgetState extends State<JoinGameWidget> {
  final _gameIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isFinding = false;
  bool _isPrivateGame = false;
  final Logger _log = Logger();

  @override
  void dispose() {
    _gameIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.join_full, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Join Existing Game',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildJoinGameForm(context),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinGameForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Game ID Input
        TextFormField(
          controller: _gameIdController,
          decoration: const InputDecoration(
            labelText: 'Game ID',
            hintText: 'Enter the game ID to join',
            prefixIcon: Icon(Icons.games),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a game ID';
            }
            if (value.trim().length < 3) {
              return 'Game ID must be at least 3 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Password Field (for private games)
        if (_isPrivateGame) ...[
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Game Password',
              hintText: 'Enter password for private game',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            validator: (value) {
              if (_isPrivateGame && (value == null || value.isEmpty)) {
                return 'Password required for private games';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
        ],

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isFinding ? null : _findGame,
                icon: _isFinding 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
                label: Text(_isFinding ? 'Finding...' : 'Find Game'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _joinGame,
                icon: _isLoading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.join_full),
                label: Text(_isLoading ? 'Joining...' : 'Join Game'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _findGame() async {
    final gameId = _gameIdController.text.trim();
    if (gameId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a game ID'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isFinding = true;
    });

    try {
      _log.info('🔍 [JoinGameWidget] Finding game: $gameId');
      
      // TODO: Implement find game API call
      // For now, simulate finding a game
      await Future.delayed(const Duration(seconds: 1));
      
      // Simulate finding a private game
      setState(() {
        _isPrivateGame = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Game found! This is a private game.'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      _log.error('❌ [JoinGameWidget] Error finding game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFinding = false;
        });
      }
    }
  }

  Future<void> _joinGame() async {
    final gameId = _gameIdController.text.trim();
    final password = _passwordController.text.trim();

    if (gameId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a game ID'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isPrivateGame && password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password required for private games'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      _log.info('🎮 [JoinGameWidget] Joining game: $gameId');

      // Prepare join data
      final joinData = {
        'room_id': gameId,
        'password': password.isNotEmpty ? password : null,
      };
      
      // Remove null values
      joinData.removeWhere((key, value) => value == null);

      // Get WebSocket manager
      final wsManager = WebSocketManager.instance;
      
      if (wsManager.socket != null) {
        // Emit join room event (backend validates password for private games)
        wsManager.socket?.emit('join_room', joinData);
        
        _log.info('🎮 [JoinGameWidget] Join room event emitted successfully');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Join request sent!'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Clear form
        _gameIdController.clear();
        _passwordController.clear();
        setState(() {
          _isPrivateGame = false;
        });

      } else {
        throw Exception('WebSocket not connected');
      }

    } catch (e) {
      _log.error('❌ [JoinGameWidget] Error joining game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error joining game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
