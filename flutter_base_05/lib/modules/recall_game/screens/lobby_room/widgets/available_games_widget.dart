import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Widget to display available games with fetch functionality
/// 
/// This widget subscribes to the recall_game state slice and displays:
/// - Available games list (if any)
/// - Fetch button to get available games
/// - Loading state during fetch
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class AvailableGamesWidget extends StatelessWidget {
  static final Logger _log = Logger();
  
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
        final recallState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Extract games-related state
        final availableGames = recallState['availableGames'] as List<dynamic>? ?? [];
        final isLoading = recallState['isLoading'] == true;
        final lastUpdated = recallState['lastUpdated'];

        _log.info('🎮 AvailableGamesWidget: ${availableGames.length} games available, loading=$isLoading');

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
                  _buildGamesList(availableGames),
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
  Widget _buildGamesList(List<dynamic> games) {
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
        ...games.map((game) => _buildGameCard(game)).toList(),
      ],
    );
  }

  /// Build individual game card
  Widget _buildGameCard(Map<String, dynamic> game) {
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
            
            // Join button
            Semantics(
              label: 'join_game_$gameId',
              identifier: 'join_game_$gameId',
              button: true,
              child: ElevatedButton(
                onPressed: () {
                  _log.info('🎮 [AvailableGamesWidget] Join game button pressed for game: $gameId');
                  // TODO: Implement join game logic
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Join'),
              ),
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
      case 'playing':
        return Colors.green;
      case 'finished':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  /// Get icon for game phase
  IconData _getPhaseIcon(String phase) {
    switch (phase.toLowerCase()) {
      case 'waiting':
        return Icons.schedule;
      case 'playing':
        return Icons.play_arrow;
      case 'finished':
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
}
