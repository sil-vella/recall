import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import 'game_phase_chip_widget.dart';
import '../../../managers/game_coordinator.dart';
import '../../../game_logic/practice_match/practice_game.dart';
import '../../../../../tools/logging/logger.dart';

/// Widget to display current game information
/// 
/// This widget subscribes to the recall_game state slice and displays:
/// - Current game details (name, ID, players, phase, status)
/// - Game start timestamp
/// - Empty state when no game is active
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class GameInfoWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false; // Enable logging for debugging start button
  
  const GameInfoWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get gameInfo state slice
        final gameInfo = recallGameState['gameInfo'] as Map<String, dynamic>? ?? {};
        final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
        final roomName = 'Game $currentGameId';
        final currentSize = gameInfo['currentSize'] ?? 0;
        final maxSize = gameInfo['maxSize'] ?? 4;
        final gamePhase = gameInfo['gamePhase']?.toString() ?? 'waiting';
        final gameStatus = gameInfo['gameStatus']?.toString() ?? 'inactive';
        final isRoomOwner = gameInfo['isRoomOwner'] ?? false;
        final isInGame = gameInfo['isInGame'] ?? false;
        
        // Check if this is a practice game
        final isPracticeGame = currentGameId.startsWith('practice_game_');
        
        // 🔍 DEBUG: Log the values that determine start button visibility
        Logger().info('🔍 GameInfoWidget DEBUG:', isOn: LOGGING_SWITCH);
        Logger().info('  currentGameId: $currentGameId', isOn: LOGGING_SWITCH);
        Logger().info('  gamePhase: $gamePhase', isOn: LOGGING_SWITCH);
        Logger().info('  isRoomOwner: $isRoomOwner', isOn: LOGGING_SWITCH);
        Logger().info('  isInGame: $isInGame', isOn: LOGGING_SWITCH);
        
        Logger().info('  Start button condition: isRoomOwner($isRoomOwner) && gamePhase($gamePhase) == "waiting" OR isPracticeGame($isPracticeGame)', isOn: LOGGING_SWITCH);
        Logger().info('  Should show start button: ${(isRoomOwner && gamePhase == 'waiting') || isPracticeGame}', isOn: LOGGING_SWITCH);
        Logger().info('  Full gameInfo: $gameInfo', isOn: LOGGING_SWITCH);
        
        // Get additional game state for context
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        if (!isInGame || currentGameId.isEmpty) {
          return _buildEmptyState();
        }
        
        return _buildGameInfoCard(
          currentGameId: currentGameId,
          roomName: roomName,
          currentSize: currentSize,
          maxSize: maxSize,
          gamePhase: gamePhase,
          gameStatus: gameStatus,
          isRoomOwner: isRoomOwner,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
          isPracticeGame: isPracticeGame,
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
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
    required bool isPracticeGame,
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
                GamePhaseChip(
                  gameId: currentGameId,
                  size: GamePhaseChipSize.medium,
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Game details - only show when not in active game (playing or out_of_turn phases)
            if (gamePhase != 'playing' && gamePhase != 'out_of_turn') ...[
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
            ],
            
            const SizedBox(height: 12),
            
            
            const SizedBox(height: 16),
            
            // Start Match Button (for room owner during waiting phase OR for practice games)
            if ((isRoomOwner && gamePhase == 'waiting') || isPracticeGame)
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
    try {
      Logger().info('🎮 GameInfoWidget: Start button pressed - initiating start match flow', isOn: LOGGING_SWITCH);
      
      // Get current game state to check if it's a practice game
      final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final gameInfo = recallGameState['gameInfo'] as Map<String, dynamic>? ?? {};
      final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
      
      Logger().info('🎮 GameInfoWidget: Current game ID: $currentGameId', isOn: LOGGING_SWITCH);
      
      // Check if this is a practice game
      final isPracticeGame = currentGameId.startsWith('practice_game_');
      Logger().info('🎮 GameInfoWidget: Practice game check - isPracticeGame: $isPracticeGame', isOn: LOGGING_SWITCH);
      
      if (isPracticeGame) {
        Logger().info('🎮 GameInfoWidget: Practice game detected - routing directly to PracticeGameCoordinator', isOn: LOGGING_SWITCH);
        
        // Route directly to practice game coordinator
        final practiceCoordinator = PracticeGameCoordinator();
        Logger().info('🎮 GameInfoWidget: Calling PracticeGameCoordinator.matchStart()', isOn: LOGGING_SWITCH);
        
        final result = await practiceCoordinator.matchStart();
        Logger().info('🎮 GameInfoWidget: PracticeGameCoordinator.matchStart() completed with result: $result', isOn: LOGGING_SWITCH);
        
      } else {
        Logger().info('🎮 GameInfoWidget: Regular game detected - routing to GameCoordinator', isOn: LOGGING_SWITCH);
        
        // Call GameCoordinator to start the match for regular games
        final gameCoordinator = GameCoordinator();
        Logger().info('🎮 GameInfoWidget: Calling GameCoordinator.startMatch()', isOn: LOGGING_SWITCH);
        
        final result = await gameCoordinator.startMatch();
        Logger().info('🎮 GameInfoWidget: GameCoordinator.startMatch() completed with result: $result', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('🎮 GameInfoWidget: Error in _handleStartMatch: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  


}
