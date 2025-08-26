/// ## CurrentGamesWidget
/// 
/// A widget that displays all games the user is currently in, with real-time updates
/// from the recall game state. This widget is state-driven and automatically updates
/// when the user joins or leaves games.
/// 
/// ### Features:
/// - **Real-time Updates**: Automatically updates when game state changes
/// - **Game Information**: Shows game details, player counts, and status
/// - **Game Actions**: Join game room or leave game functionality
/// - **State-Driven**: Reads from validated recall game state
/// - **Multiple Games**: Displays all games user is currently in
/// 
/// ### State Subscription:
/// - Subscribes to `recall_game` state slice
/// - Reads `joinedGames`, `totalJoinedGames`, `joinedGamesTimestamp`
/// - Automatically rebuilds when state changes
/// 
/// ### Game Data Structure:
/// ```dart
/// {
///   'game_id': 'room_123',
///   'room_id': 'room_123', 
///   'game_state': {
///     'gameId': 'room_123',
///     'gameName': 'Recall Game room_123',
///     'playerCount': 1,
///     'maxPlayers': 6,
///     'minPlayers': 2,
///     'phase': 'waiting',
///     'status': 'inactive',
///     'permission': 'public'
///   },
///   'joined_at': '2025-08-25T14:21:53.009561'
/// }
/// ```
/// 
/// ### Event Emissions:
/// - Uses `WSEventManager.leaveRoom()` for leaving games
/// - Emits `leave_room` WebSocket event (backend handles room/game cleanup)
/// - Backend automatically removes user from both room and game

import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/websockets/ws_event_manager.dart';
import '../../../../../tools/logging/logger.dart';

class CurrentGamesWidget extends StatelessWidget {
  final Function(String) onJoinGame;
  static final Logger _log = Logger();

  const CurrentGamesWidget({
    Key? key,
    required this.onJoinGame,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get recall game state for joined games
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Extract joined games from recall game state
        final joinedGames = recallGameState['joinedGames'] as List<dynamic>? ?? [];
        final totalJoinedGames = recallGameState['totalJoinedGames'] ?? 0;
        final joinedGamesTimestamp = recallGameState['joinedGamesTimestamp']?.toString() ?? '';

        _log.info('🎮 CurrentGamesWidget: Found $totalJoinedGames joined games');
        _log.info('🎮 CurrentGamesWidget: Joined games data: $joinedGames');

        if (joinedGames.isNotEmpty) {
          final firstGame = joinedGames.first as Map<String, dynamic>;
          _log.info('🎮 CurrentGamesWidget: First game data: $firstGame');
          
          final gameState = firstGame['game_state'] as Map<String, dynamic>? ?? {};
          _log.info('🎮 CurrentGamesWidget: First game state: $gameState');
        }

        return _buildJoinedGamesList(
          context,
          joinedGames: joinedGames.cast<Map<String, dynamic>>(),
          totalJoinedGames: totalJoinedGames,
          timestamp: joinedGamesTimestamp,
        );
      },
    );
  }

  Widget _buildJoinedGamesList(
    BuildContext context, {
    required List<Map<String, dynamic>> joinedGames,
    required int totalJoinedGames,
    required String timestamp,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with game count and timestamp
            Row(
              children: [
                Icon(Icons.games, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Joined Games ($totalJoinedGames)',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (timestamp.isNotEmpty)
                  Text(
                    'Updated: ${_formatTimestamp(timestamp)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // List of joined games
            if (joinedGames.isEmpty)
              _buildEmptyState(context)
            else
              ...joinedGames.map((gameData) => _buildGameCard(context, gameData: gameData)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Icon(
            Icons.games_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Games Joined',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Join a game to see it here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, {required Map<String, dynamic> gameData}) {
    // Extract game information from the state data (which comes from the event)
    final gameId = gameData['game_id']?.toString() ?? '';
    final roomId = gameData['room_id']?.toString() ?? gameId;

    // Get game state from the nested game_state object (this is the actual game data from backend)
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};

    // Extract data from the game_state object (this is what the backend sends)
    final roomName = gameState['gameName']?.toString() ?? 'Game $gameId';
    final currentSize = gameState['playerCount'] ?? 0;
    final maxSize = gameState['maxPlayers'] ?? 4;
    final minSize = gameState['minPlayers'] ?? 2;
    final permission = gameState['permission']?.toString() ?? 'public';
    final gamePhase = gameState['phase']?.toString() ?? 'waiting';
    final gameStatus = gameState['status']?.toString() ?? 'inactive';

    _log.info('🎮 [CurrentGamesWidget] Game state for $gameId: $gameState');
    _log.info('🎮 [CurrentGamesWidget] Extracted data for $gameId: currentSize=$currentSize, maxSize=$maxSize, minSize=$minSize, permission=$permission, gamePhase=$gamePhase, gameStatus=$gameStatus');

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Game header
            Row(
              children: [
                Icon(
                  _getGamePhaseIcon(gamePhase),
                  color: _getGamePhaseColor(gamePhase),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Game ID: $gameId',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPermissionBadge(permission),
              ],
            ),
            const SizedBox(height: 12),

            // Game details
            _buildGameDetails(
              context,
              currentSize: currentSize,
              maxSize: maxSize,
              minSize: minSize,
              gamePhase: gamePhase,
              gameStatus: gameStatus,
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startGame(context, roomId),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Game'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _joinGameRoom(context, gameId),
                    icon: const Icon(Icons.games),
                    label: const Text('Game Room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _leaveGame(context, roomId),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Leave'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameDetails(
    BuildContext context, {
    required int currentSize,
    required int maxSize,
    required int minSize,
    required String gamePhase,
    required String gameStatus,
  }) {
    return Column(
      children: [
        // Player count
        Row(
          children: [
            const Icon(Icons.people, size: 16),
            const SizedBox(width: 4),
            Text(
              'Players: $currentSize/$maxSize',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              'Min: $minSize',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Game phase and status
        Row(
          children: [
            const Icon(Icons.info_outline, size: 16),
            const SizedBox(width: 4),
            Text(
              'Phase: ${_formatGamePhase(gamePhase)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              'Status: ${_formatGameStatus(gameStatus)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPermissionBadge(String permission) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: permission == 'private' ? Colors.orange : Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        permission.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  IconData _getGamePhaseIcon(String phase) {
    switch (phase.toLowerCase()) {
      case 'waiting':
        return Icons.hourglass_empty;
      case 'playing':
        return Icons.play_circle;
      case 'recall':
        return Icons.flag;
      case 'ended':
        return Icons.stop_circle;
      default:
        return Icons.games;
    }
  }

  Color _getGamePhaseColor(String phase) {
    switch (phase.toLowerCase()) {
      case 'waiting':
        return Colors.orange;
      case 'playing':
        return Colors.green;
      case 'recall':
        return Colors.red;
      case 'ended':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _formatGamePhase(String phase) {
    switch (phase.toLowerCase()) {
      case 'waiting':
        return 'Waiting for Players';
      case 'playing':
        return 'In Progress';
      case 'recall':
        return 'Recall Called';
      case 'ended':
        return 'Game Ended';
      default:
        return phase;
    }
  }

  String _formatGameStatus(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'inactive':
        return 'Inactive';
      case 'full':
        return 'Full';
      default:
        return status;
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  void _startGame(BuildContext context, String roomId) {
    _log.info('🎮 [CurrentGamesWidget] Start game button pressed for room: $roomId');
    // TODO: Implement start game functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Start game functionality coming soon!'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _joinGameRoom(BuildContext context, String gameId) {
    _log.info('🎮 [CurrentGamesWidget] Game Room button pressed for game: $gameId');
    
    // Check if user is already in this game
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final joinedGames = recallGameState['joinedGames'] as List<dynamic>? ?? [];
    
    final isAlreadyInGame = joinedGames.any((game) => 
      (game as Map<String, dynamic>)['game_id'] == gameId
    );

    if (isAlreadyInGame) {
      _log.info('🎮 [CurrentGamesWidget] User already in game, not triggering join_room event');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in this game!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Call the callback to join the game
    onJoinGame(gameId);
  }

  void _leaveGame(BuildContext context, String roomId) {
    _log.info('🚪 [CurrentGamesWidget] Leave game button pressed for game: $roomId');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave Game'),
          content: Text('Are you sure you want to leave this game?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _leaveRoom(roomId);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );
  }

  /// Leave room using core WebSocket system
  void _leaveRoom(String roomId) {
    try {
      _log.info('🚪 [CurrentGamesWidget] Leaving room: $roomId');
      
      // Use the core WebSocket event manager
      final wsEventManager = WSEventManager.instance;
      
      // Leave room using the proper method
      wsEventManager.leaveRoom(roomId).then((result) {
        if (result['pending'] != null) {
          _log.info('🚪 [CurrentGamesWidget] Leave room request sent, waiting for server response');
        } else if (result['success'] != null) {
          _log.info('✅ [CurrentGamesWidget] Left room successfully');
        } else {
          _log.error('❌ [CurrentGamesWidget] Failed to leave room: ${result['error']}');
        }
      }).catchError((e) {
        _log.error('❌ [CurrentGamesWidget] Error leaving room: $e');
      });
      
    } catch (e) {
      _log.error('❌ [CurrentGamesWidget] Error leaving room: $e');
    }
  }
}
