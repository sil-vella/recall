import 'package:flutter/material.dart';
import '../../../../../../core/managers/state_manager.dart';
import '../../../../../../utils/consts/theme_consts.dart';

/// Unified Player Status Chip Widget
/// 
/// This widget handles its own state subscription and provides a consistent
/// status chip display for player statuses across the Cleco game.
/// 
/// Features:
/// - Self-contained state management using ListenableBuilder
/// - Consistent styling and behavior across all usage contexts
/// - Support for all player statuses defined in the backend
/// - Reusable across different widgets (opponents_panel, my_hand, etc.)
/// 
/// Usage:
/// ```dart
/// PlayerStatusChip(
///   playerId: 'player_123', // Required: ID of the player to show status for
///   size: PlayerStatusChipSize.small, // Optional: small, medium, large
/// )
/// ```
class PlayerStatusChip extends StatelessWidget {
  final String playerId;
  final PlayerStatusChipSize size;
  final String? customStatus; // Optional: override status from state

  const PlayerStatusChip({
    Key? key,
    required this.playerId,
    this.size = PlayerStatusChipSize.small,
    this.customStatus,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get the player status from state
        String playerStatus = customStatus ?? _getPlayerStatusFromState();
        
        return _buildStatusChip(playerStatus);
      },
    );
  }

  /// Get player status from the global state (derived from SSOT)
  String _getPlayerStatusFromState() {
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    
    // Check if this is the current user (the actual user playing the game)
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    if (playerId == currentUserId) {
      // This is the current user - get status from myHand slice (computed from SSOT)
      final myHand = clecoGameState['myHand'] as Map<String, dynamic>? ?? {};
      return myHand['playerStatus']?.toString() ?? 'unknown';
    } else {
      // This is an opponent - get status from opponents panel (which comes from SSOT)
      final opponentsPanel = clecoGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
      final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
      
      // Find the specific opponent
      for (final opponent in opponents) {
        if (opponent['id']?.toString() == playerId) {
          // Opponent status comes directly from SSOT (games[gameId].gameData.game_state.players[])
          return opponent['status']?.toString() ?? 'unknown';
        }
      }
      
      return 'unknown';
    }
  }

  /// Build the status chip with appropriate styling
  Widget _buildStatusChip(String status) {
    final statusData = _getStatusData(status);
    
    return Container(
      padding: _getPadding(),
      decoration: BoxDecoration(
        color: statusData.color,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusData.icon,
            size: _getIconSize(),
            color: AppColors.textOnAccent,
          ),
          SizedBox(width: _getSpacing()),
          Text(
            statusData.text,
            style: AppTextStyles.bodySmall().copyWith(
              color: AppColors.textOnAccent,
              fontSize: _getFontSize(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Get status data (color, text, icon) for a given status
  _StatusData _getStatusData(String status) {
    switch (status) {
      case 'waiting':
        return _StatusData(
          color: Colors.grey,
          text: 'Waiting',
          icon: Icons.schedule,
        );
      case 'ready':
        return _StatusData(
          color: Colors.blue,
          text: 'Ready',
          icon: Icons.check_circle,
        );
      case 'drawing_card':
        return _StatusData(
          color: Colors.orange,
          text: 'Drawing',
          icon: Icons.draw,
        );
      case 'playing_card':
        return _StatusData(
          color: Colors.green,
          text: 'Playing',
          icon: Icons.play_arrow,
        );
      case 'same_rank_window':
        return _StatusData(
          color: Colors.purple,
          text: 'Same Rank',
          icon: Icons.flash_on,
        );
      case 'queen_peek':
        return _StatusData(
          color: Colors.pink,
          text: 'Queen Peek',
          icon: Icons.visibility,
        );
      case 'jack_swap':
        return _StatusData(
          color: Colors.indigo,
          text: 'Jack Swap',
          icon: Icons.swap_horiz,
        );
      case 'peeking':
        return _StatusData(
          color: Colors.cyan,
          text: 'Peeking',
          icon: Icons.visibility,
        );
      case 'initial_peek':
        return _StatusData(
          color: Colors.teal,
          text: 'Initial Peek',
          icon: Icons.visibility_outlined,
        );
      case 'winner':
        return _StatusData(
          color: Colors.green,
          text: 'Winner',
          icon: Icons.emoji_events,
        );
      case 'finished':
        return _StatusData(
          color: Colors.red,
          text: 'Finished',
          icon: Icons.stop,
        );
      case 'disconnected':
        return _StatusData(
          color: AppColors.errorColor,
          text: 'Disconnected',
          icon: Icons.wifi_off,
        );
      default:
        return _StatusData(
          color: AppColors.textSecondary,
          text: 'Unknown',
          icon: Icons.help,
        );
    }
  }

  /// Get padding based on size
  EdgeInsets _getPadding() {
    switch (size) {
      case PlayerStatusChipSize.small:
        return const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
      case PlayerStatusChipSize.medium:
        return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
      case PlayerStatusChipSize.large:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    }
  }

  /// Get border radius based on size
  double _getBorderRadius() {
    switch (size) {
      case PlayerStatusChipSize.small:
        return 10;
      case PlayerStatusChipSize.medium:
        return 12;
      case PlayerStatusChipSize.large:
        return 14;
    }
  }

  /// Get icon size based on size
  double _getIconSize() {
    switch (size) {
      case PlayerStatusChipSize.small:
        return 12;
      case PlayerStatusChipSize.medium:
        return 14;
      case PlayerStatusChipSize.large:
        return 16;
    }
  }

  /// Get spacing between icon and text based on size
  double _getSpacing() {
    switch (size) {
      case PlayerStatusChipSize.small:
        return 4;
      case PlayerStatusChipSize.medium:
        return 6;
      case PlayerStatusChipSize.large:
        return 8;
    }
  }

  /// Get font size based on size
  double _getFontSize() {
    switch (size) {
      case PlayerStatusChipSize.small:
        return 10;
      case PlayerStatusChipSize.medium:
        return 12;
      case PlayerStatusChipSize.large:
        return 14;
    }
  }
}

/// Size options for the PlayerStatusChip
enum PlayerStatusChipSize {
  small,
  medium,
  large,
}

/// Internal data class for status information
class _StatusData {
  final Color color;
  final String text;
  final IconData icon;

  _StatusData({
    required this.color,
    required this.text,
    required this.icon,
  });
}
