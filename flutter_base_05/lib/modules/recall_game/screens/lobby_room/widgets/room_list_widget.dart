import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../services/recall_game_coordinator.dart';
import '../../../../../tools/logging/logger.dart';

class RoomListWidget extends StatelessWidget {
  static final Logger _log = Logger();
  final String title;
  final Function(String) onJoinRoom;
  final Function(String) onLeaveRoom;
  final String emptyMessage;
  final String roomType; // 'public' or 'my'

  const RoomListWidget({
    Key? key,
    required this.title,
    required this.onJoinRoom,
    required this.onLeaveRoom,
    required this.emptyMessage,
    required this.roomType,
  }) : super(key: key);

  Future<void> _joinGame(BuildContext context, String roomId) async {
    try {
      _log.info('🎮 Joining game for room: $roomId');
      
      // First join the room if not already in it
      final currentRoomId = StateManager().getModuleState<Map<String, dynamic>>('recall_game')?['currentRoomId'];
      if (currentRoomId != roomId) {
        _log.info('🔄 Joining room: $roomId (currently in: $currentRoomId)');
        await onJoinRoom(roomId);
      } else {
        _log.info('✅ Already in room: $roomId');
      }
      
      // Then join the game as a player
      final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final playerName = (login['username'] ?? login['email'] ?? 'Player').toString();
      
      _log.info('🎮 Joining game as: $playerName');
      final gameCoordinator = RecallGameCoordinator(); // Use singleton instance
      final joinResult = await gameCoordinator.joinGameAndRoom(roomId, playerName);
      if (joinResult['error'] != null) {
        _showSnackBar(context, 'Failed to join game: ${joinResult['error']}', isError: true);
        return;
      }
      
      // Navigate to game screen (match will be started from there)
      _log.info('🎯 Navigating to game screen...');
      NavigationManager().navigateTo('/recall/game-play');
      
    } catch (e) {
      _log.error('❌ Error joining game: $e');
      _showSnackBar(context, 'Error joining game: $e', isError: true);
    }
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get active games tracking
        final activeGames = Map<String, Map<String, dynamic>>.from(recall['activeGames'] ?? {});
        
        // Only show user's created rooms (no public room lists in state)
        List<Map<String, dynamic>> rooms;
        if (roomType == 'my') {
          rooms = (recall['myCreatedRooms'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
        } else {
          // For public rooms, show empty list since we don't store public room lists in state
          rooms = const [];
        }

        if (rooms.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyMessage),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...rooms.map((room) => _RoomTile(
                  room: room,
                  activeGames: activeGames,
                  onJoinRoom: () => _joinGame(context, room['room_id']),
                  onLeaveRoom: () => onLeaveRoom(room['room_id']),
                )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoomTile extends StatelessWidget {
  final Map<String, dynamic> room;
  final Map<String, Map<String, dynamic>> activeGames;
  final VoidCallback onJoinRoom;
  final VoidCallback onLeaveRoom;

  const _RoomTile({
    required this.room,
    required this.activeGames,
    required this.onJoinRoom,
    required this.onLeaveRoom,
  });

  @override
  Widget build(BuildContext context) {
    final roomId = room['room_id'] as String? ?? '';
    final roomName = room['room_name'] as String? ?? roomId;
    final maxPlayers = room['max_size'] as int? ?? 4;
    final currentSize = room['current_size'] as int? ?? 0;
    final permission = room['permission'] as String? ?? 'public';
    
    // Check if this room has an active game
    final gameInfo = activeGames[roomId];
    final hasActiveGame = gameInfo != null;
    final gamePhase = gameInfo?['gamePhase'] ?? 'waiting';
    final gameStatus = gameInfo?['gameStatus'] ?? 'inactive';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Room ID: $roomId'),
                    Text('Players: $currentSize/$maxPlayers'),
                    Text('Permission: $permission'),
                    if (hasActiveGame) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Game: $gamePhase ($gameStatus)',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  if (hasActiveGame && gameStatus == 'active')
                    ElevatedButton(
                      onPressed: onJoinRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Join Game'),
                    )
                  else if (hasActiveGame && gameStatus == 'inactive')
                    ElevatedButton(
                      onPressed: onJoinRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Go to Game Room'),
                    )
                  else
                    ElevatedButton(
                      onPressed: onJoinRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Join Room'),
                    ),
                  const SizedBox(height: 4),
                  ElevatedButton(
                    onPressed: onLeaveRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Leave'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
} 