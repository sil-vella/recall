import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/websockets/ws_event_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Widget to display all joined rooms with join functionality
/// 
/// This widget subscribes to both recall_game and websocket state slices and displays:
/// - All rooms the user is currently in (from WebSocket state)
/// - Room details (name, size, permission, game phase)
/// - Join button for room actions
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class CurrentRoomWidget extends StatelessWidget {
  static final Logger _log = Logger();
  
  final Function(String)? onJoinRoom;
  
  const CurrentRoomWidget({
    Key? key,
    this.onJoinRoom,
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
        
        _log.info('🎮 CurrentRoomWidget: Found $totalJoinedGames joined games');
        _log.info('🎮 CurrentRoomWidget: Joined games data: $joinedGames');
        
        if (joinedGames.isNotEmpty) {
          final firstGame = joinedGames.first as Map<String, dynamic>;
          _log.info('🎮 CurrentRoomWidget: First game data: $firstGame');
          if (firstGame.containsKey('game_state')) {
            final gameState = firstGame['game_state'] as Map<String, dynamic>;
            _log.info('🎮 CurrentRoomWidget: First game state: $gameState');
          }
        }

        // If not in any games, show empty state
        if (totalJoinedGames == 0 || joinedGames.isEmpty) {
          return _buildEmptyState();
        }

        // Show all joined games
        return _buildJoinedGamesList(
          context,
          joinedGames: joinedGames.cast<Map<String, dynamic>>(),
          totalJoinedGames: totalJoinedGames,
          timestamp: joinedGamesTimestamp,
        );
      },
    );
  }

  /// Build empty state when user is not in any games
  Widget _buildEmptyState() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.games, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Joined Games',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Not currently in any games',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new room or join an existing one to start playing',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build list of all joined games
  Widget _buildJoinedGamesList(
    BuildContext context, {
    required List<Map<String, dynamic>> joinedGames,
    required int totalJoinedGames,
    required String timestamp,
  }) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with count and timestamp
            Row(
              children: [
                Icon(Icons.games, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Joined Games ($totalJoinedGames)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (timestamp.isNotEmpty)
                  Text(
                    'Updated: ${_formatTimestamp(timestamp)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // List of joined games
            ...joinedGames.map((gameData) => _buildGameCard(
              context,
              gameData: gameData,
            )).toList(),
          ],
        ),
      ),
    );
  }

  /// Build game card with game information from state data
  Widget _buildGameCard(
    BuildContext context, {
    required Map<String, dynamic> gameData,
  }) {
    // Extract game information from the state data (which comes from the event)
    final gameId = gameData['game_id']?.toString() ?? '';
    final roomId = gameData['room_id']?.toString() ?? gameId;
    
    // Get game state from the nested game_state object (this is the actual game data from backend)
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    _log.info('🎮 [CurrentRoomWidget] Game state for $gameId: $gameState');
    
    // Extract data from the game_state object (this is what the backend sends)
    final roomName = gameState['gameName']?.toString() ?? 'Game $gameId';
    final currentSize = gameState['playerCount'] ?? 0;
    final maxSize = gameState['maxPlayers'] ?? 4;
    final minSize = gameState['minPlayers'] ?? 2;
    final permission = gameState['permission']?.toString() ?? 'public';
    final gamePhase = gameState['phase']?.toString() ?? 'waiting';
    final gameStatus = gameState['status']?.toString() ?? 'inactive';
    
    // Determine if user is game owner (this might need to be passed from the event)
    final isGameOwner = gameData['owner_id']?.toString() == gameData['user_id']?.toString();
    final isInGame = true; // If we're showing this game, user is in it
    
    _log.info('🎮 [CurrentRoomWidget] Extracted data for $gameId: currentSize=$currentSize, maxSize=$maxSize, minSize=$minSize, permission=$permission, gamePhase=$gamePhase, gameStatus=$gameStatus');
    
    final canStartGame = isGameOwner && 
                        gamePhase == 'waiting' && 
                        currentSize >= minSize;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with room name and status
            Row(
              children: [
                Icon(
                  Icons.room,
                  color: gameStatus == 'active' ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    roomName.isNotEmpty ? roomName : 'Room $roomId',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusChip(gamePhase, gameStatus),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Game details
            _buildGameDetails(
              gameId: gameId,
              roomId: roomId,
              currentSize: currentSize,
              maxSize: maxSize,
              minSize: minSize,
              permission: permission,
              isGameOwner: isGameOwner,
            ),
            
            const SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                if (canStartGame)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _log.info('🎮 [CurrentRoomWidget] Start game button pressed for room: $roomId');
                        // TODO: Implement start game logic
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Game'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                
                if (canStartGame) const SizedBox(width: 8),
                
                // Game Room button - only show if user is in game
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isInGame ? () {
                      _log.info('🎮 [CurrentRoomWidget] Game Room button pressed for game: $gameId');
                      // Don't call onJoinRoom since user is already in the game
                      // This prevents duplicate join_room events that corrupt the state
                      _log.info('🎮 [CurrentRoomWidget] User already in game, not triggering join_room event');
                    } : null,
                    icon: const Icon(Icons.games),
                    label: const Text('Game Room'),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Leave Game button
                ElevatedButton.icon(
                  onPressed: () {
                    _log.info('🚪 [CurrentRoomWidget] Leave game button pressed for game: $gameId');
                    _leaveRoom(roomId);
                  },
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Leave'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build game details section
  Widget _buildGameDetails({
    required String gameId,
    required String roomId,
    required int currentSize,
    required int maxSize,
    required int minSize,
    required String permission,
    required bool isGameOwner,
  }) {
    return Column(
      children: [
        // Room ID
        Row(
          children: [
            Icon(Icons.tag, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              'ID: $roomId',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 4),
        
        // Player count
        Row(
          children: [
            Icon(Icons.people, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              'Players: $currentSize/$maxSize (min: $minSize)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 4),
        
        // Room permission
        Row(
          children: [
            Icon(
              permission == 'private' ? Icons.lock : Icons.public,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
                           Text(
                 permission.toUpperCase(),
                 style: TextStyle(
                   fontSize: 12,
                   color: Colors.grey[600],
                 ),
               ),
          ],
        ),
        
        const SizedBox(height: 4),
        
        // Game owner indicator
        if (isGameOwner)
          Row(
            children: [
              Icon(Icons.star, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                'You are the room owner',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Build status chip based on game phase and status
  Widget _buildStatusChip(String gamePhase, String gameStatus) {
    Color chipColor;
    String chipText;
    IconData chipIcon;

    switch (gamePhase) {
      case 'waiting':
        chipColor = Colors.orange;
        chipText = 'Waiting';
        chipIcon = Icons.schedule;
        break;
      case 'playing':
        chipColor = Colors.green;
        chipText = 'Playing';
        chipIcon = Icons.play_arrow;
        break;
      case 'finished':
        chipColor = Colors.grey;
        chipText = 'Finished';
        chipIcon = Icons.stop;
        break;
      default:
        chipColor = Colors.grey;
        chipText = 'Unknown';
        chipIcon = Icons.help;
    }

         return Chip(
       avatar: Icon(chipIcon, size: 16, color: Colors.white),
      label: Text(
        chipText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: chipColor,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// Format timestamp for display
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

  /// Leave room using core WebSocket system
  void _leaveRoom(String roomId) {
    try {
      _log.info('🚪 [CurrentRoomWidget] Leaving room: $roomId');
      
      // Use the core WebSocket event manager
      final wsEventManager = WSEventManager.instance;
      
      // Leave room using the proper method
      wsEventManager.leaveRoom(roomId).then((result) {
        if (result['pending'] != null) {
          _log.info('🚪 [CurrentRoomWidget] Leave room request sent, waiting for server response');
        } else if (result['success'] != null) {
          _log.info('✅ [CurrentRoomWidget] Left room successfully');
        } else {
          _log.error('❌ [CurrentRoomWidget] Failed to leave room: ${result['error']}');
        }
      }).catchError((e) {
        _log.error('❌ [CurrentRoomWidget] Error leaving room: $e');
      });
      
    } catch (e) {
      _log.error('❌ [CurrentRoomWidget] Error leaving room: $e');
    }
  }
}
