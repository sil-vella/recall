import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
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
        // Get websocket state for joined rooms
        final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        
        // Extract joined rooms from WebSocket state
        final joinedRooms = websocketState['joinedRooms'] as List<dynamic>? ?? [];
        final totalJoinedRooms = websocketState['totalJoinedRooms'] ?? 0;
        final joinedRoomsTimestamp = websocketState['joinedRoomsTimestamp']?.toString() ?? '';
        
        _log.info('🏠 CurrentRoomWidget: Found $totalJoinedRooms joined rooms');

        // If not in any rooms, show empty state
        if (totalJoinedRooms == 0 || joinedRooms.isEmpty) {
          return _buildEmptyState();
        }

        // Show all joined rooms
        return _buildJoinedRoomsList(
          context,
          joinedRooms: joinedRooms.cast<Map<String, dynamic>>(),
          totalJoinedRooms: totalJoinedRooms,
          timestamp: joinedRoomsTimestamp,
        );
      },
    );
  }

  /// Build empty state when user is not in a room
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
                Icon(Icons.room, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Joined Rooms',
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
              'Not currently in any rooms',
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

  /// Build list of all joined rooms
  Widget _buildJoinedRoomsList(
    BuildContext context, {
    required List<Map<String, dynamic>> joinedRooms,
    required int totalJoinedRooms,
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
                Icon(Icons.room, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Joined Rooms ($totalJoinedRooms)',
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
            
            // List of joined rooms
            ...joinedRooms.map((roomData) => _buildRoomCard(
              context,
              roomData: roomData,
            )).toList(),
          ],
        ),
      ),
    );
  }

  /// Build room card with room information from data
  Widget _buildRoomCard(
    BuildContext context, {
    required Map<String, dynamic> roomData,
  }) {
    // Extract room information from the data
    final roomId = roomData['room_id']?.toString() ?? '';
    final roomName = roomData['room_name']?.toString() ?? 'Room $roomId';
    final currentSize = roomData['size'] ?? 0;
    final maxSize = roomData['max_size'] ?? 4;
    final minSize = roomData['min_players'] ?? 2;
    final permission = roomData['permission']?.toString() ?? 'public';
    final isRoomOwner = roomData['creator_id']?.toString() == roomData['user_id']?.toString();
    final gamePhase = roomData['game_phase']?.toString() ?? 'waiting';
    final gameStatus = roomData['game_status']?.toString() ?? 'inactive';
    final isInRoom = true; // If we're showing this room, user is in it
    
    final canStartGame = isRoomOwner && 
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
            
            // Room details
            _buildRoomDetails(
              roomId: roomId,
              currentSize: currentSize,
              maxSize: maxSize,
              minSize: minSize,
              permission: permission,
              isRoomOwner: isRoomOwner,
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
                
                // Game Room button - only show if user is in room
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isInRoom ? () {
                      _log.info('🎮 [CurrentRoomWidget] Game Room button pressed for room: $roomId');
                      // Don't call onJoinRoom since user is already in the room
                      // This prevents duplicate join_room events that corrupt the state
                      _log.info('🎮 [CurrentRoomWidget] User already in room, not triggering join_room event');
                    } : null,
                    icon: const Icon(Icons.games),
                    label: const Text('Game Room'),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Leave Room button
                ElevatedButton.icon(
                  onPressed: () {
                    _log.info('🚪 [CurrentRoomWidget] Leave room button pressed for room: $roomId');
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

  /// Build room details section
  Widget _buildRoomDetails({
    required String roomId,
    required int currentSize,
    required int maxSize,
    required int minSize,
    required String permission,
    required bool isRoomOwner,
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
        
        // Room owner indicator
        if (isRoomOwner)
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

  /// Leave room by emitting WebSocket event
  void _leaveRoom(String roomId) {
    try {
      _log.info('🚪 [CurrentRoomWidget] Emitting leave_room event for room: $roomId');
      
      // Get WebSocket manager instance
      final wsManager = WebSocketManager.instance;
      
      // Emit leave_room event
      wsManager.socket?.emit('leave_room', {
        'room_id': roomId,
      });
      
      _log.info('🚪 [CurrentRoomWidget] Leave room event emitted successfully');
      
    } catch (e) {
      _log.error('❌ [CurrentRoomWidget] Error leaving room: $e');
    }
  }
}
