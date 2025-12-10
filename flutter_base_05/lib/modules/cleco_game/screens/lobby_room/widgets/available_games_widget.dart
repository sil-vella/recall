import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/game_coordinator.dart';
import '../../../../cleco_game/utils/cleco_game_helpers.dart';

/// Widget to display available games with fetch functionality
/// 
/// This widget subscribes to the cleco_game state slice and displays:
/// - Available games list (if any)
/// - Fetch button to get available games
/// - Loading state during fetch
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class AvailableGamesWidget extends StatelessWidget {
  final Function()? onFetchGames;
  
  const AvailableGamesWidget({
    Key? key,
    this.onFetchGames,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final clecoState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        
        // Note: We could get current user ID from login state if needed in the future
        // final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
        
        // Extract games-related state
        final availableGames = clecoState['availableGames'] as List<dynamic>? ?? [];
        final joinedGamesSlice = clecoState['joinedGamesSlice'] as Map<String, dynamic>? ?? {};
        final joinedGames = joinedGamesSlice['games'] as List<dynamic>? ?? [];
        final isLoading = clecoState['isLoading'] == true;
        final lastUpdated = clecoState['lastUpdated'];
        
        // Create a set of game IDs that the user is already in for quick lookup
        final Set<String> userJoinedGameIds = joinedGames
            .map((game) => game['game_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and fetch button
                Row(
                  children: [
                    Icon(Icons.games, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    const Text(
                      'Available Games',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      label: 'fetch_available_games',
                      identifier: 'fetch_available_games',
                      button: true,
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : onFetchGames,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        icon: isLoading 
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 16),
                        label: Text(isLoading ? 'Fetching...' : 'Fetch Games'),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Last updated info
                if (lastUpdated != null)
                  Text(
                    'Last updated: ${_formatTimestamp(lastUpdated)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Games list or empty state
                if (availableGames.isEmpty)
                  _buildEmptyState()
                else
                  _buildGamesList(availableGames, userJoinedGameIds),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build empty state when no games are available
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.games_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'No games available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Fetch Games" to find available games you can join',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build list of available games
  Widget _buildGamesList(List<dynamic> games, Set<String> userJoinedGameIds) {
    return Column(
      children: [
        Text(
          '${games.length} game${games.length == 1 ? '' : 's'} available',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        ...games.map((game) => _buildGameCard(game, userJoinedGameIds)).toList(),
      ],
    );
  }

  /// Build individual game card
  Widget _buildGameCard(Map<String, dynamic> game, Set<String> userJoinedGameIds) {
    final gameId = game['gameId']?.toString() ?? 'Unknown';
    final gameName = game['gameName']?.toString() ?? 'Unnamed Game';
    final playerCount = game['playerCount'] ?? 0;
    final maxPlayers = game['maxPlayers'] ?? 4;
    final minPlayers = game['minPlayers'] ?? 2;
    final phase = game['phase']?.toString() ?? 'waiting';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Game icon and status
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getPhaseColor(phase),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getPhaseIcon(phase),
                color: Colors.white,
                size: 20,
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Game details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gameName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Players: $playerCount/$maxPlayers (min: $minPlayers)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Phase: ${phase.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            
            // Join/Leave button based on user's current status
            Builder(
              builder: (context) {
                final isUserInGame = userJoinedGameIds.contains(gameId);
                
                if (isUserInGame) {
                  // User is already in this game - show Leave button
                  return Semantics(
                    label: 'leave_game_$gameId',
                    identifier: 'leave_game_$gameId',
                    button: true,
                    child: ElevatedButton(
                      onPressed: () {
                        _leaveGame(gameId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text('Leave'),
                    ),
                  );
                } else {
                  // User is not in this game - show Join button
                  return Semantics(
                    label: 'join_game_$gameId',
                    identifier: 'join_game_$gameId',
                    button: true,
                    child: ElevatedButton(
                      onPressed: () {
                        _joinGame(context, gameId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text('Join'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Get color for game phase
  Color _getPhaseColor(String phase) {
    switch (phase.toLowerCase()) {
      case 'waiting':
        return Colors.orange;
      case 'setup':
        return Colors.blue;
      case 'playing':
        return Colors.green;
      case 'out_of_turn':
        return Colors.blue;
      case 'same_rank_window':
        return Colors.purple;
      case 'special_play_window':
        return Colors.amber;
      case 'queen_peek_window':
        return Colors.purple;
      case 'turn_pending_events':
        return Colors.teal;
      case 'ending_round':
        return Colors.orange;
      case 'ending_turn':
        return Colors.orange;
      case 'cleco':
        return Colors.red;
      case 'finished':
        return Colors.grey;
      case 'game_ended':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  /// Get icon for game phase
  IconData _getPhaseIcon(String phase) {
    switch (phase.toLowerCase()) {
      case 'waiting':
        return Icons.schedule;
      case 'setup':
        return Icons.settings;
      case 'playing':
        return Icons.play_arrow;
      case 'out_of_turn':
        return Icons.flash_on;
      case 'same_rank_window':
        return Icons.flash_on;
      case 'special_play_window':
        return Icons.star;
      case 'queen_peek_window':
        return Icons.visibility;
      case 'turn_pending_events':
        return Icons.hourglass_empty;
      case 'ending_round':
        return Icons.stop;
      case 'ending_turn':
        return Icons.stop;
      case 'cleco':
        return Icons.warning;
      case 'finished':
        return Icons.stop;
      case 'game_ended':
        return Icons.stop;
      default:
        return Icons.help;
    }
  }

  /// Format timestamp for display
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Never';
    
    try {
      if (timestamp is String) {
        final dateTime = DateTime.parse(timestamp);
        return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      }
      return 'Unknown';
    } catch (e) {
      return 'Invalid';
    }
  }

  /// Join a game using GameCoordinator
  void _joinGame(BuildContext context, String gameId) {
    try {
      // Check if user has enough coins (default 25)
      if (!ClecoGameHelpers.checkCoinsRequirement()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Insufficient coins to join a game. Required: 25'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Use GameCoordinator to join the game
      final gameCoordinator = GameCoordinator();
      gameCoordinator.joinGame(gameId: gameId, playerName: 'Player');
    } catch (e) {
      // Handle error silently
    }
  }

  /// Leave a game using GameCoordinator
  void _leaveGame(String gameId) {
    try {
      // Use GameCoordinator to leave the game
      final gameCoordinator = GameCoordinator();
      gameCoordinator.leaveGame(gameId: gameId);
    } catch (e) {
      // Handle error silently
    }
  }
}
