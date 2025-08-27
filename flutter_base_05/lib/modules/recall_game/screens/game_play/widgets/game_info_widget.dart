import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../managers/game_coordinator.dart';

/// Widget to display current game information
/// 
/// This widget subscribes to the recall_game state slice and displays:
/// - Current game details (name, ID, players, phase, status)
/// - Game start timestamp
/// - Empty state when no game is active
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class GameInfoWidget extends StatelessWidget {
  static final Logger _log = Logger();
  
  const GameInfoWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
        final currentGameData = recallGameState['currentGameData'] as Map<String, dynamic>? ?? {};
        final isInGame = recallGameState['isInGame'] == true;
        final isRoomOwner = recallGameState['isRoomOwner'] ?? false;
        
        _log.info('🎮 GameInfoWidget: isInGame=$isInGame, currentGameId=$currentGameId');
        
        if (!isInGame || currentGameId.isEmpty) {
          return _buildEmptyState();
        }
        
        // Extract game state information
        final gameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
        final roomName = gameState['gameName']?.toString() ?? 'Game $currentGameId';
        final currentSize = gameState['playerCount'] ?? 0;
        final maxSize = gameState['maxPlayers'] ?? 4;
        final gamePhase = gameState['phase']?.toString() ?? 'waiting';
        final gameStatus = gameState['status']?.toString() ?? 'inactive';
        

        
        _log.info('🎮 GameInfoWidget: Game data - roomName=$roomName, currentSize=$currentSize, maxSize=$maxSize, phase=$gamePhase, status=$gameStatus');
        
        return _buildGameInfoCard(
          currentGameId: currentGameId,
          roomName: roomName,
          currentSize: currentSize,
          maxSize: maxSize,
          gamePhase: gamePhase,
          gameStatus: gameStatus,
          isRoomOwner: isRoomOwner,
        );
      },
    );
  }

  /// Build empty state when no game is active
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
                Icon(Icons.info, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Game Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'No active game found',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Return to the lobby to join a game',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build game information card
  Widget _buildGameInfoCard({
    required String currentGameId,
    required String roomName,
    required int currentSize,
    required int maxSize,
    required String gamePhase,
    required String gameStatus,
    required bool isRoomOwner,
  }) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.games, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    roomName,
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
            Row(
              children: [
                Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Game ID: $currentGameId',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 4),
            
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Players: $currentSize/$maxSize',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Start Match Button (only for room owner during waiting phase)
            if (isRoomOwner && gamePhase == 'waiting')
              _buildStartMatchButton(),
          ],
        ),
      ),
    );
  }
  
  /// Build start match button
  Widget _buildStartMatchButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _handleStartMatch,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text(
          'Start Match',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
  
  /// Handle start match button press
  void _handleStartMatch() async {
    _log.info('🎮 GameInfoWidget: Start match button pressed');
    
    try {
      // Call GameCoordinator to start the match
      final gameCoordinator = GameCoordinator();
      final success = await gameCoordinator.startMatch();
      
      if (success) {
        _log.info('✅ GameInfoWidget: Start match action sent successfully');
      } else {
        _log.error('❌ GameInfoWidget: Failed to send start match action');
      }
    } catch (e) {
      _log.error('❌ GameInfoWidget: Error in start match action: $e');
    }
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
