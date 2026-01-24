import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../game_play/widgets/game_phase_chip_widget.dart';
import '../../../managers/game_coordinator.dart';
import '../../../../dutch_game/utils/dutch_game_helpers.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = false; // Enabled for lobby screen recomputation debugging

/// Widget to display all joined rooms with join functionality
/// 
/// This widget subscribes to both dutch_game and websocket state slices and displays:
/// - All rooms the user is currently in (from WebSocket state)
/// - Room details (name, size, permission, game phase)
/// - Join button for room actions
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class CurrentRoomWidget extends StatelessWidget {
  static final Logger _logger = Logger();
  final Function(String)? onJoinRoom;
  
  const CurrentRoomWidget({
    Key? key,
    this.onJoinRoom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // CRITICAL: Force recomputation of joinedGamesSlice when widget builds
    // This ensures the widget always reflects the current games map state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
      final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      
      if (LOGGING_SWITCH) {
        _logger.info('CurrentRoomWidget: build() - Forcing joinedGamesSlice recomputation (games map has ${games.length} games)');
      }
      
      // Trigger recomputation by updating games (even if unchanged, this will recompute the slice)
      DutchGameHelpers.updateUIState({
        'games': games, // This will trigger _updateWidgetSlices which will recompute joinedGamesSlice
      });
    });

    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get dutch game state for joined games
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get current user ID from login state
        final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
        final currentUserId = loginState['userId']?.toString() ?? '';
        
        // Extract joined games from the joinedGamesSlice state slice
        final joinedGamesSlice = dutchGameState['joinedGamesSlice'] as Map<String, dynamic>? ?? {};
        final joinedGames = joinedGamesSlice['games'] as List<dynamic>? ?? [];
        final totalJoinedGames = joinedGamesSlice['totalGames'] ?? 0;
        
        if (LOGGING_SWITCH) {
          _logger.info('CurrentRoomWidget: Rendering with ${totalJoinedGames} games from joinedGamesSlice');
        }
        // Removed joinedGamesTimestamp - causes unnecessary state updates

        // If not in any games, show empty state
        if (totalJoinedGames == 0 || joinedGames.isEmpty) {
          return _buildEmptyState();
        }

        // Show all joined games
        return _buildJoinedGamesList(
          context,
          joinedGames: joinedGames.cast<Map<String, dynamic>>(),
          totalJoinedGames: totalJoinedGames,
          // Removed timestamp parameter - no longer needed
          currentUserId: currentUserId,
        );
      },
    );
  }

  /// Build empty state when user is not in any games
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
              'Joined Games',
              style: AppTextStyles.headingSmall(),
            ),
            const SizedBox(height: 12),
            Text(
              'Not currently in any games',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new game or join an existing one to start playing',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
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
    // Removed timestamp parameter - no longer needed
    required String currentUserId,
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
            // Header with count
            Text(
              'Joined Games ($totalJoinedGames)',
              style: AppTextStyles.headingSmall(),
            ),
          
          const SizedBox(height: 16),
          
          // List of joined games
          ...joinedGames.map((gameData) => _buildGameCard(
            context,
            gameData: gameData,
            currentUserId: currentUserId,
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
    required String currentUserId,
  }) {
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
    
    // Determine if user is game owner by comparing current user ID with owner_id
    final ownerId = gameData['owner_id']?.toString() ?? '';
    final isGameOwner = currentUserId.isNotEmpty && ownerId.isNotEmpty && currentUserId == ownerId;
    
    final canStartGame = isGameOwner && 
                        gamePhase == 'waiting' && 
                        currentSize >= minSize;

    return Padding(
      padding: AppPadding.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with room name and status
          Row(
            children: [
              Icon(
                Icons.room,
                color: gameStatus == 'active' ? AppColors.successColor : AppColors.infoColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  roomName.isNotEmpty ? roomName : 'Room $roomId',
                  style: AppTextStyles.bodyLarge().copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GamePhaseChip(
                gameId: gameId,
                size: GamePhaseChipSize.small,
              ),
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
                      // TODO: Implement start game logic
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Game'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.successColor,
                      foregroundColor: AppColors.textOnAccent,
                    ),
                  ),
                ),
              
              if (canStartGame) const SizedBox(width: 8),
              
              // Enter Game Room button - navigate to game play screen
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _enterGameRoom(context, gameData);
                  },
                  icon: const Icon(Icons.games),
                  label: const Text('Enter Game Room'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.infoColor,
                    foregroundColor: AppColors.textOnAccent,
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Leave Game button
              ElevatedButton.icon(
                onPressed: () {
                  _leaveRoom(roomId);
                },
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Leave'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.errorColor,
                  foregroundColor: AppColors.textOnAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Navigate to game play screen with game data
  void _enterGameRoom(BuildContext context, Map<String, dynamic> gameData) async {
    try {
      // Clean up dutch game state before joining real game            
      // Store game data in state for the game play screen to access
      final gameId = gameData['game_id']?.toString() ?? '';
      
      // Extract game state information
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      final gamePhase = gameState['phase']?.toString() ?? 'waiting';
      final gameStatus = gameState['status']?.toString() ?? 'inactive';
      
      // Determine if current user is room owner (re-get login state after potential cleanup)
      final updatedLoginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final updatedUserId = updatedLoginState['userId']?.toString() ?? '';
      final isRoomOwner = gameData['owner_id']?.toString() == updatedUserId;
      
      // Get current games map
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Add/update the current game in the games map
      // Note: playerCount and maxSize are read directly from gameData in the widget slice computation
      games[gameId] = {
        'gameData': gameData,  // This is the single source of truth
        'gamePhase': gamePhase,
        'gameStatus': gameStatus,
        'isRoomOwner': isRoomOwner,
        'isInGame': true,
        'joinedAt': DateTime.now().toIso8601String(),
      };
      
      // Update dutch game state with current game data using validated state updater
      DutchGameHelpers.updateUIState({
        'currentGameId': gameId,
        'games': games,
      });
      
      // Navigate to game play screen
      NavigationManager().navigateTo('/dutch/game-play');
      
    } catch (e) {
      // Handle error silently
    }
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
            Icon(Icons.tag, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              'ID: $roomId',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 4),
        
        // Player count
        Row(
          children: [
            Icon(Icons.people, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              'Players: $currentSize/$maxSize (min: $minSize)',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
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
                 style: AppTextStyles.bodySmall().copyWith(
                   color: AppColors.textSecondary,
                 ),
               ),
          ],
        ),
        
        const SizedBox(height: 4),
        
        // Game owner indicator
        if (isGameOwner)
          Row(
            children: [
              Icon(Icons.star, size: 16, color: AppColors.warningColor),
              const SizedBox(width: 4),
              Text(
                'You are the room owner',
                style: AppTextStyles.bodySmall().copyWith(
                  color: AppColors.warningColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Build status chip based on game phase and status

  // Removed _formatTimestamp - no longer needed after removing timestamps

  /// Leave room using GameCoordinator
  void _leaveRoom(String roomId) {
    try {
      // Use GameCoordinator to leave the room
      final gameCoordinator = GameCoordinator();
      gameCoordinator.leaveGame(gameId: roomId);
    } catch (e) {
      // Handle error silently
    }
  }
}
