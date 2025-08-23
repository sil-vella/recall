import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Widget to display current room information with join functionality
/// 
/// This widget subscribes to the recall_game state slice and displays:
/// - Current room information (if user is in a room)
/// - Room details (name, size, permission)
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
        final recallState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Extract room-related state
        final isInRoom = recallState['isInRoom'] == true;
        final currentRoomId = recallState['currentRoomId']?.toString() ?? '';
        final roomName = recallState['roomName']?.toString() ?? '';
        final currentSize = recallState['currentSize'] ?? 0;
        final maxSize = recallState['maxSize'] ?? 4;
        final minSize = recallState['minSize'] ?? 2;
        final permission = recallState['permission']?.toString() ?? 'public';
        final isRoomOwner = recallState['isRoomOwner'] == true;
        final gamePhase = recallState['gamePhase']?.toString() ?? 'waiting';
        final gameStatus = recallState['gameStatus']?.toString() ?? 'inactive';

        _log.info('🏠 CurrentRoomWidget: isInRoom=$isInRoom, roomId=$currentRoomId, size=$currentSize/$maxSize');

        // If not in a room, show empty state
        if (!isInRoom || currentRoomId.isEmpty) {
          return _buildEmptyState();
        }

        // Show current room information
        return _buildRoomCard(
          context,
          roomId: currentRoomId,
          roomName: roomName,
          currentSize: currentSize,
          maxSize: maxSize,
          minSize: minSize,
          permission: permission,
          isRoomOwner: isRoomOwner,
          gamePhase: gamePhase,
          gameStatus: gameStatus,
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
                  'Current Room',
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
              'Not currently in a room',
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

  /// Build room card with current room information
  Widget _buildRoomCard(
    BuildContext context, {
    required String roomId,
    required String roomName,
    required int currentSize,
    required int maxSize,
    required int minSize,
    required String permission,
    required bool isRoomOwner,
    required String gamePhase,
    required String gameStatus,
  }) {
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
                
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onJoinRoom != null ? () {
                      _log.info('🚪 [CurrentRoomWidget] Join button pressed for room: $roomId');
                      onJoinRoom!(roomId);
                    } : null,
                    icon: const Icon(Icons.group_add),
                    label: const Text('Join Room'),
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
}
