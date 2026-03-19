import 'package:flutter/material.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../../tools/logging/logger.dart';
// import '../../../backend_core/utils/level_matcher.dart'; // used by frontend coin check (bypassed for backend test)
import '../../../../dutch_game/utils/dutch_game_helpers.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../backend_core/utils/level_matcher.dart';

// Enable for random game join debugging (logs to console / server.log)
const bool LOGGING_SWITCH = false;

/// Widget to join a random available game
/// 
/// Provides a single button that:
/// - Searches for available public games
/// - Joins a random available game if found
/// - Auto-creates and auto-starts a new game if none available
class JoinRandomGameWidget extends StatefulWidget {
  final VoidCallback? onJoinRandomGame;
  
  const JoinRandomGameWidget({
    Key? key,
    this.onJoinRandomGame,
  }) : super(key: key);

  @override
  State<JoinRandomGameWidget> createState() => _JoinRandomGameWidgetState();
}

class _JoinRandomGameWidgetState extends State<JoinRandomGameWidget> {
  bool _isLoading = false;
  /// Room table tier (1–4) sent with join_random_game as `game_level`.
  int _selectedTableLevel = LevelMatcher.levelOrder.first;
  static final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    // Listen for join room errors from backend
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.on('join_room_error', (data) {
      if (mounted) {
        final error = data['message'] ?? data['error'] ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Join random game failed: $error'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        // Reset loading state
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    // Remove WebSocket listeners
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.off('join_room_error');
    super.dispose();
  }

  Future<void> _handleJoinRandomGame({required bool isClearAndCollect}) async {
    if (_isLoading) return;
    if (LOGGING_SWITCH) {
      _logger.info('🎯 JoinRandomGame: button pressed (isClearAndCollect=$isClearAndCollect)', isOn: true);
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Frontend coin check bypassed to test backend coin check
      // final hasEnoughCoins = await DutchGameHelpers.checkCoinsRequirement(fetchFromAPI: true);
      // if (LOGGING_SWITCH) {
      //   _logger.info('🎯 JoinRandomGame: coins check hasEnoughCoins=$hasEnoughCoins', isOn: true);
      // }
      // if (!hasEnoughCoins) {
      //   setState(() {
      //     _isLoading = false;
      //   });
      //   if (mounted) {
      //     ScaffoldMessenger.of(context).showSnackBar(
      //       SnackBar(
      //         content: Text('Insufficient coins to join a game. Required: ${LevelMatcher.levelToCoinFee(null, defaultFee: 25)}'),
      //         backgroundColor: AppColors.errorColor,
      //       ),
      //     );
      //   }
      //   return;
      // }

      // Ensure WebSocket is ready before attempting to join
      final isReady = await DutchGameHelpers.ensureWebSocketReady();
      if (LOGGING_SWITCH) {
        _logger.info('🎯 JoinRandomGame: WebSocket ready=$isReady', isOn: true);
      }
      if (!isReady) {
        return;
      }
      
      // Use the helper method to join random game with isClearAndCollect flag
      final result = await DutchGameHelpers.joinRandomGame(
        isClearAndCollect: isClearAndCollect,
        gameLevel: _selectedTableLevel,
      );
      if (LOGGING_SWITCH) {
        _logger.info('🎯 JoinRandomGame: result success=${result['success']}, error=${result['error']}', isOn: true);
      }
      
      if (result['success'] == true) {
        final message = result['message'] ?? 'Joining random game...';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.successColor,
            ),
          );
        }
        
        // Call optional callback
        widget.onJoinRandomGame?.call();
      } else {
        final errorMessage = result['error'] ?? 'Failed to join random game';
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join random game: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Join',
              style: AppTextStyles.headingSmall().copyWith(color: AppColors.white),
            ),
            SizedBox(height: AppPadding.mediumPadding.top),
            Text(
              'Join a random available game',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            Text(
              'Table level',
              style: AppTextStyles.label().copyWith(
                color: AppColors.white,
              ),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  surface: AppColors.widgetContainerBackground,
                  onSurface: AppColors.white,
                ),
              ),
              child: Semantics(
                label: 'join_random_dropdown_table_level',
                identifier: 'join_random_dropdown_table_level',
                child: DropdownButtonFormField<int>(
                  value: LevelMatcher.levelOrder.contains(_selectedTableLevel)
                      ? _selectedTableLevel
                      : LevelMatcher.levelOrder.first,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppPadding.defaultPadding.left,
                      vertical: AppPadding.mediumPadding.top,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.borderFocused),
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                    filled: true,
                    fillColor: AppColors.primaryColor,
                  ),
                  dropdownColor: AppColors.widgetContainerBackground,
                  style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                  items: LevelMatcher.levelOrder.map((level) {
                    final title = LevelMatcher.levelToTitle(level);
                    return DropdownMenuItem<int>(
                      value: level,
                      child: Text(
                        '$level — $title',
                        style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selectedTableLevel = value);
                          }
                        },
                ),
              ),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            Text(
              'Select Game Type',
              style: AppTextStyles.label().copyWith(
                color: AppColors.white,
              ),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            // Classic (no collection)
            Semantics(
              label: 'join_random_game_clear',
              identifier: 'join_random_game_clear',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _handleJoinRandomGame(isClearAndCollect: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentColor,
                    foregroundColor: AppColors.textOnAccent,
                    padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
                  ),
                  icon: _isLoading
                    ? SizedBox(
                        height: AppSizes.iconSmall,
                        width: AppSizes.iconSmall,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnAccent,
                        ),
                      )
                    : Icon(Icons.shuffle, size: AppSizes.iconSmall),
                  label: Text(
                    _isLoading ? 'Joining...' : 'Classic',
                    style: AppTextStyles.bodyMedium().copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnAccent,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: AppPadding.mediumPadding.top),
            // Clear and Collect (collection mode)
            Semantics(
              label: 'join_random_game_collection',
              identifier: 'join_random_game_collection',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _handleJoinRandomGame(isClearAndCollect: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentColor,
                    foregroundColor: AppColors.textOnAccent,
                    padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
                  ),
                  icon: _isLoading
                    ? SizedBox(
                        height: AppSizes.iconSmall,
                        width: AppSizes.iconSmall,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnAccent,
                        ),
                      )
                    : Icon(Icons.casino, size: AppSizes.iconSmall),
                  label: Text(
                    _isLoading ? 'Joining...' : 'Clear and Collect',
                    style: AppTextStyles.bodyMedium().copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnAccent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

