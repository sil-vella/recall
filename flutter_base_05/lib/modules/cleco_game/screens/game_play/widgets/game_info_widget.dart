import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/game_coordinator.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Widget to display current game information
/// 
/// This widget subscribes to the cleco_game state slice and displays:
/// - Current game details (name, ID, players, phase, status)
/// - Game start timestamp
/// - Empty state when no game is active
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class GameInfoWidget extends StatefulWidget {
  const GameInfoWidget({Key? key}) : super(key: key);

  @override
  State<GameInfoWidget> createState() => _GameInfoWidgetState();
}

class _GameInfoWidgetState extends State<GameInfoWidget> {
  static const bool LOGGING_SWITCH = false; // Enable logging for debugging start button
  static final Logger _logger = Logger();
  bool _isStartingMatch = false;
  
  String? _getPhaseFromGamesMap(Map<String, dynamic> games, String gameId) {
    if (gameId.isEmpty || !games.containsKey(gameId)) {
      return null;
    }
    
    final gameEntry = games[gameId] as Map<String, dynamic>? ?? {};
    final gameData = gameEntry['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final rawPhase = gameState['phase']?.toString();
    
    return _normalizePhase(rawPhase);
  }
  
  String? _normalizePhase(String? rawPhase) {
    if (rawPhase == null || rawPhase.isEmpty) {
      return null;
    }
    
    switch (rawPhase) {
      case 'waiting_for_players':
        return 'waiting';
      case 'dealing_cards':
        return 'setup';
      case 'player_turn':
      case 'same_rank_window':
      case 'special_play_window':
      case 'queen_peek_window':
      case 'turn_pending_events':
      case 'ending_round':
      case 'ending_turn':
      case 'cleco_called':
        return 'playing';
      default:
        return rawPhase;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get gameInfo state slice
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        final gameInfo = clecoGameState['gameInfo'] as Map<String, dynamic>? ?? {};
        final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
        final roomName = 'Game $currentGameId';
        final currentSize = gameInfo['currentSize'] ?? 0;
        final maxSize = gameInfo['maxSize'] ?? 4;
        
        // Derive phase from SSOT (games map) with fallback to gameInfo slice
        final ssotPhase = _getPhaseFromGamesMap(games, currentGameId);
        final gamePhase = ssotPhase ?? gameInfo['gamePhase']?.toString() ?? 'waiting';
        
        // Reset loading state if match has started
        if (_isStartingMatch && gamePhase != 'waiting' && gamePhase != 'setup') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isStartingMatch = false;
              });
            }
          });
        }
        final gameStatus = gameInfo['gameStatus']?.toString() ?? 'inactive';
        final isRoomOwner = gameInfo['isRoomOwner'] ?? false;
        final isInGame = gameInfo['isInGame'] ?? false;
        
        // Check if this is a practice game (practice games start with 'practice_room_')
        final isPracticeGame = currentGameId.startsWith('practice_room_');
        
        // 🔍 DEBUG: Log the values that determine start button visibility
        _logger.info('🔍 GameInfoWidget DEBUG:', isOn: LOGGING_SWITCH);
        _logger.info('  currentGameId: $currentGameId', isOn: LOGGING_SWITCH);
        _logger.info('  gamePhase: $gamePhase', isOn: LOGGING_SWITCH);
        _logger.info('  isRoomOwner: $isRoomOwner', isOn: LOGGING_SWITCH);
        _logger.info('  isInGame: $isInGame', isOn: LOGGING_SWITCH);
        
        _logger.info('  Start button condition: isPracticeGame($isPracticeGame) && gamePhase($gamePhase) == "waiting"', isOn: LOGGING_SWITCH);
        _logger.info('  Should show start button: ${isPracticeGame && gamePhase == 'waiting'}', isOn: LOGGING_SWITCH);
        _logger.info('  Full gameInfo: $gameInfo', isOn: LOGGING_SWITCH);
        
        // Get additional game state for context
        final isGameActive = clecoGameState['isGameActive'] ?? false;
        final isMyTurn = clecoGameState['isMyTurn'] ?? false;
        // Derive playerStatus from SSOT if needed (currently not used in GameInfoWidget)
        // For now, we'll derive it from myHand slice if needed
        final myHand = clecoGameState['myHand'] as Map<String, dynamic>? ?? {};
        final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
        
        if (!isInGame || currentGameId.isEmpty) {
          return _buildEmptyState();
        }
        
        // Hide entire widget when match has started
        // Match has started when game phase is not 'waiting' or 'setup'
        final matchHasStarted = gamePhase != 'waiting' && gamePhase != 'setup';
        if (matchHasStarted) {
          return const SizedBox.shrink();
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
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game Information',
              style: AppTextStyles.headingSmall(),
            ),
            const SizedBox(height: 12),
            Text(
              'No active game found',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Return to the lobby to join a game',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
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
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roomName,
              style: AppTextStyles.headingSmall(),
            ),
            
            const SizedBox(height: 12),
            
            // Game details - only show when not in active game (playing or out_of_turn phases)
            if (gamePhase != 'playing' && gamePhase != 'out_of_turn') ...[
              Row(
                children: [
                  Icon(Icons.tag, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Game ID: $currentGameId',
                    style: AppTextStyles.bodySmall().copyWith(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 4),
              
              Row(
                children: [
                  Icon(Icons.people, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Players: $currentSize/$maxSize',
                    style: AppTextStyles.bodySmall().copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 12),
            
            
            const SizedBox(height: 16),
            
            // Start Match Button (for practice games in waiting phase)
            if (isPracticeGame && gamePhase == 'waiting')
              _buildStartMatchButton(isLoading: _isStartingMatch),
          ],
        ),
      ),
    );
  }
  
  /// Build start match button
  Widget _buildStartMatchButton({bool isLoading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : _handleStartMatch,
        icon: isLoading 
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnAccent),
              ),
            )
          : const Icon(Icons.play_arrow, size: 18),
        label: Text(
          isLoading ? 'Starting Match...' : 'Start Match',
          style: AppTextStyles.bodyMedium().copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isLoading ? AppColors.disabledColor : AppColors.successColor,
          foregroundColor: AppColors.textOnAccent,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          disabledBackgroundColor: AppColors.disabledColor,
        ),
      ),
    );
  }
  
  /// Handle start match button press
  void _handleStartMatch() async {
    try {
      // Set loading state
      setState(() {
        _isStartingMatch = true;
      });
      
      _logger.info('🎮 GameInfoWidget: ===== START MATCH BUTTON PRESSED =====', isOn: LOGGING_SWITCH);
      _logger.info('🎮 GameInfoWidget: Initiating start match flow', isOn: LOGGING_SWITCH);
      
      // Get current game state to check if it's a cleco game
      final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final gameInfo = clecoGameState['gameInfo'] as Map<String, dynamic>? ?? {};
      final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
      final currentGamePhase = gameInfo['gamePhase']?.toString() ?? 'unknown';
      
      _logger.info('🎮 GameInfoWidget: Current game ID: $currentGameId', isOn: LOGGING_SWITCH);
      _logger.info('🎮 GameInfoWidget: Current game phase: $currentGamePhase', isOn: LOGGING_SWITCH);
      
      // Check if this is a practice game (practice games start with 'practice_room_')
      final isPracticeGame = currentGameId.startsWith('practice_room_');
      _logger.info('🎮 GameInfoWidget: Cleco game check - isPracticeGame: $isPracticeGame', isOn: LOGGING_SWITCH);
      
      // Use GameCoordinator for both practice and multiplayer games
      // The event emitter will route to practice bridge if transport mode is practice
      final gameCoordinator = GameCoordinator();
      
      if (isPracticeGame) {
        _logger.info('🎮 GameInfoWidget: Practice game detected - routing to GameCoordinator (will use practice bridge)', isOn: LOGGING_SWITCH);
      } else {
        _logger.info('🎮 GameInfoWidget: Regular game detected - routing to GameCoordinator', isOn: LOGGING_SWITCH);
      }
      
      _logger.info('🎮 GameInfoWidget: Calling GameCoordinator.startMatch()', isOn: LOGGING_SWITCH);
      final result = await gameCoordinator.startMatch();
      _logger.info('🎮 GameInfoWidget: GameCoordinator.startMatch() completed with result: $result', isOn: LOGGING_SWITCH);
      
      _logger.info('🎮 GameInfoWidget: ===== START MATCH FLOW COMPLETED =====', isOn: LOGGING_SWITCH);
      
      // Reset loading state after a delay to allow UI to update
      // The widget will hide when gamePhase changes, but we reset here as a fallback
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isStartingMatch = false;
          });
        }
      });
      
    } catch (e, stackTrace) {
      _logger.error('🎮 GameInfoWidget: ❌ Error in _handleStartMatch: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      
      // Reset loading state on error
      if (mounted) {
        setState(() {
          _isStartingMatch = false;
        });
      }
    }
  }
  
  


}
