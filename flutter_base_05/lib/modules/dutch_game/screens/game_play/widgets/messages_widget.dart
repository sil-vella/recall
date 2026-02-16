import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../managers/dutch_event_handler_callbacks.dart';

/// Decoder for .lottie (dotlottie zip) assets: picks the first .json animation.
Future<LottieComposition?> _decodeDotLottie(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      for (final f in files) {
        if (f.name.endsWith('.json')) return f;
      }
      return files.isNotEmpty ? files.first : null;
    },
  );
}

/// Loads winner Lottie composition; returns null on any error (e.g. startFrame == endFrame assertion).
Future<LottieComposition?> _loadWinnerLottieSafe() async {
  try {
    final data = await rootBundle.load('assets/lottie/winner01.lottie');
    final bytes = data.buffer.asUint8List();
    return await _decodeDotLottie(bytes).catchError((_, __) => null);
  } catch (_) {
    return null;
  }
}

/// Messages Widget for Dutch Game
/// 
/// This widget displays game messages as a modal overlay.
/// It's hidden by default and only shows when messages are triggered.
/// Used for match notifications like "Match Starting", "Match Over", "Winner", "Points", etc.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MessagesWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false; // Enabled for winner modal debugging
  static final Logger _logger = Logger();
  
  const MessagesWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get messages state slice
        final messagesData = dutchGameState['messages'] as Map<String, dynamic>? ?? {};
        final isVisible = messagesData['isVisible'] ?? false;
        final title = messagesData['title']?.toString() ?? 'Game Message';
        final content = messagesData['content']?.toString() ?? '';
        final messageType = messagesData['type']?.toString() ?? 'info'; // info, success, warning, error
        final showCloseButton = messagesData['showCloseButton'] ?? true;
        final autoClose = messagesData['autoClose'] ?? false;
        final autoCloseDelay = messagesData['autoCloseDelay'] ?? 3000; // milliseconds
        
        // Get game phase to ensure modal only shows when game has ended
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? '';
        final isGameEnded = gamePhase == 'game_ended';
        
        final contentPreview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
        if (LOGGING_SWITCH) {
          _logger.info('📬 MessagesWidget: State update - isVisible=$isVisible, gamePhase=$gamePhase, isGameEnded=$isGameEnded, title="$title", content="$contentPreview", type=$messageType');
        }
        if (LOGGING_SWITCH) {
          _logger.info('📬 MessagesWidget: Full messagesData keys: ${messagesData.keys.toList()}');
        }
        
        // Don't render if not visible, or game hasn't ended (allow empty content when we have ordered winners)
        if (!isVisible || !isGameEnded) {
          if (LOGGING_SWITCH) {
            _logger.info('📬 MessagesWidget: Not rendering - isVisible=$isVisible, isGameEnded=$isGameEnded');
          }
          return const SizedBox.shrink();
        }
        
        // Get ordered winners list from current game state for end-of-game popup
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>?;
        final gameData = currentGame?['gameData'] as Map<String, dynamic>?;
        final gameState = gameData?['game_state'] as Map<String, dynamic>?;
        final orderedWinners = gameState?['winners'] as List<dynamic>?;
        final hasOrderedWinners = orderedWinners != null && orderedWinners.isNotEmpty;
        if (!hasOrderedWinners && content.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('📬 MessagesWidget: Not rendering - content empty and no ordered winners');
          }
          return const SizedBox.shrink();
        }
        
        final isCurrentUserWinner = messagesData['isCurrentUserWinner'] == true;
        if (LOGGING_SWITCH) {
          _logger.info('📬 MessagesWidget: Rendering modal with title="$title" (game phase is game_ended), isCurrentUserWinner=$isCurrentUserWinner');
        }
        
        return _buildModalOverlay(
          context,
          title,
          content,
          messageType,
          showCloseButton,
          autoClose,
          autoCloseDelay,
          orderedWinners: hasOrderedWinners ? orderedWinners : null,
          isCurrentUserWinner: isCurrentUserWinner,
        );
      },
    );
  }
  
  Widget _buildModalOverlay(
    BuildContext context,
    String title,
    String content,
    String messageType,
    bool showCloseButton,
    bool autoClose,
    int autoCloseDelay, {
    List<dynamic>? orderedWinners,
    bool isCurrentUserWinner = false,
  }) {
    // Auto-close timer if enabled
    if (autoClose) {
      Future.delayed(Duration(milliseconds: autoCloseDelay), () {
        _closeMessage(context);
      });
    }
    
    final messageTypeColor = _getMessageTypeColor(context, messageType);
    // Blend message type color with widget container background for better contrast
    // Use 15% message color + 85% container background to create a subtle tinted header
    final headerBackgroundColor = Color.lerp(
      AppColors.widgetContainerBackground,
      messageTypeColor,
      0.15,
    ) ?? AppColors.widgetContainerBackground;
    // Calculate text color based on the header background to ensure readability
    final headerTextColor = ThemeConfig.getTextColorForBackground(headerBackgroundColor);
    
    final modalContent = Material(
      color: AppColors.black.withValues(alpha: 0.54), // Semi-transparent background
      child: Center(
        child: Container(
          margin: AppPadding.defaultPadding,
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 600,
          ),
          decoration: BoxDecoration(
            color: AppColors.widgetContainerBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Container(
                padding: AppPadding.cardPadding,
                decoration: BoxDecoration(
                  color: headerBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getMessageTypeIcon(messageType),
                      color: messageTypeColor,
                      size: 24,
                    ),
                    SizedBox(width: AppPadding.smallPadding.left),
                    Expanded(
                      child: Text(
                        title,
                        style: AppTextStyles.headingSmall().copyWith(
                          color: headerTextColor,
                        ),
                      ),
                    ),
                    if (showCloseButton)
                      IconButton(
                        onPressed: () => _closeMessage(context),
                        icon: Icon(
                          Icons.close,
                          color: headerTextColor,
                        ),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),

              // Winner trophy/Lottie inside modal, just above the players list (only when current user won)
              if (orderedWinners != null && orderedWinners.isNotEmpty && isCurrentUserWinner)
                _WinnerTrophyInModal(),

              // Content area: ordered winners list (game ended) or plain message
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: orderedWinners != null && orderedWinners.isNotEmpty
                      ? _buildOrderedWinnersContent(orderedWinners)
                      : Text(
                          content,
                          style: AppTextStyles.bodyMedium().copyWith(
                            color: AppColors.white,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),

              // User stats row (wins, losses, draws, coins) when game ended – same source as account screen
              if (orderedWinners != null && orderedWinners.isNotEmpty)
                _buildEndGameUserStats(),

              // Footer with close button (if enabled)
              if (showCloseButton)
                Container(
                  padding: AppPadding.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.cardVariant,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _closeMessage(context),
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textOnCard,
                        ),
                        label: Text(
                          'Close',
                          style: AppTextStyles.buttonText().copyWith(
                            color: AppColors.textOnCard,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textOnCard,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    
    return modalContent;
  }
  
  /// Build content for game-ended popup: ordered list (winners at top, then by points).
  /// Active user is shown as "You" and colored with accent (green) unless they are winner (gold).
  Widget _buildOrderedWinnersContent(List<dynamic> orderedWinners) {
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();

    String winTypeLabel(dynamic winType) {
      switch (winType?.toString()) {
        case 'four_of_a_kind':
          return 'Four of a Kind';
        case 'empty_hand':
          return 'No Cards Left';
        case 'lowest_points':
          return 'Lowest Points';
        case 'dutch':
          return 'Dutch Called';
        default:
          return 'Winner';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < orderedWinners.length; i++) ...[
          if (i > 0) SizedBox(height: AppPadding.smallPadding.top),
          Builder(
            builder: (context) {
              final e = orderedWinners[i];
              if (e is! Map<String, dynamic>) return const SizedBox.shrink();
              final playerId = e['playerId']?.toString() ?? '';
              final name = e['playerName']?.toString() ?? 'Unknown';
              final winType = e['winType'];
              final points = e['points'] as int?;
              final cardCount = e['cardCount'] as int?;
              final isWinner = winType != null && winType.toString().isNotEmpty;
              final isCurrentUser = currentUserId.isNotEmpty && playerId == currentUserId;
              final displayName = isCurrentUser ? 'You' : name;
              // Winner: gold; else current user: green accent; else default
              final rowColor = isWinner
                  ? AppColors.matchPotGold
                  : (isCurrentUser ? AppColors.accentColor : AppColors.white);
              final secondaryColor = isWinner
                  ? AppColors.matchPotGold
                  : (isCurrentUser ? AppColors.accentColor : AppColors.textSecondary);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: secondaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      displayName,
                      style: AppTextStyles.bodyMedium().copyWith(
                        color: rowColor,
                        fontWeight: isWinner ? FontWeight.w600 : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    isWinner
                        ? ' (${winTypeLabel(winType)}) — ${points ?? 0} pts, ${cardCount ?? 0} cards'
                        : (points != null && cardCount != null
                            ? ' — ${points} pts, $cardCount cards'
                            : ''),
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: secondaryColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  /// User stats row at bottom of end-game modal (wins, losses, draws, coins) from dutch_game userStats, same as account screen.
  Widget _buildEndGameUserStats() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final userStats = dutchGameState['userStats'] as Map<String, dynamic>?;
    if (userStats == null) return const SizedBox.shrink();

    final wins = userStats['wins'] as int? ?? 0;
    final losses = userStats['losses'] as int? ?? 0;
    final totalMatches = userStats['total_matches'] as int? ?? 0;
    final draws = totalMatches - wins - losses;
    final coins = userStats['coins'] as int? ?? 0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppPadding.cardPadding.left,
        vertical: AppPadding.smallPadding.top,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: EdgeInsets.only(
        left: AppPadding.cardPadding.left,
        right: AppPadding.cardPadding.right,
        bottom: AppPadding.smallPadding.top,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statChip(Icons.emoji_events, 'Wins', wins.toString(), AppColors.successColor),
          _statChip(Icons.trending_down, 'Losses', losses.toString(), AppColors.errorColor),
          _statChip(Icons.handshake, 'Draws', draws.toString(), AppColors.textSecondary),
          _statChip(Icons.monetization_on, 'Coins', coins.toString(), AppColors.matchPotGold),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.bodyMedium().copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.label().copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Color _getMessageTypeColor(BuildContext context, String messageType) {
    switch (messageType) {
      case 'success':
        return AppColors.successColor;
      case 'warning':
        return AppColors.warningColor;
      case 'error':
        return AppColors.errorColor;
      case 'info':
      default:
        return AppColors.infoColor;
    }
  }
  
  IconData _getMessageTypeIcon(String messageType) {
    switch (messageType) {
      case 'success':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning;
      case 'error':
        return Icons.error;
      case 'info':
      default:
        return Icons.info;
    }
  }
  
  void _closeMessage(BuildContext context) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('MessagesWidget: Closing message modal');
      }
      
      final wasGameEnded = StateManager().getModuleState<Map<String, dynamic>>('dutch_game')?['gamePhase']?.toString() == 'game_ended';
      
      // Update state to hide messages
      StateManager().updateModuleState('dutch_game', {
        'messages': {
          'isVisible': false,
          'title': '',
          'content': '',
          'type': 'info',
          'showCloseButton': true,
          'autoClose': false,
          'autoCloseDelay': 3000,
        },
      });
      
      if (wasGameEnded) {
        NavigationManager().navigateTo('/dutch/lobby');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('MessagesWidget: Failed to close message: $e');
      }
    }
  }
}

/// Trophy/Lottie shown inside the modal just above the players list when current user won.
class _WinnerTrophyInModal extends StatefulWidget {
  @override
  State<_WinnerTrophyInModal> createState() => _WinnerTrophyInModalState();
}

class _WinnerTrophyInModalState extends State<_WinnerTrophyInModal>
    with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _entryScale;
  late Animation<double> _pulseScale;
  late Future<LottieComposition?> _compositionFuture;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _entryScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.elasticOut),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 1), weight: 1),
    ]).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _entryController.forward();
    _entryController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.repeat(reverse: true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _pulseController.stop();
        });
      }
    });
    _compositionFuture = _loadWinnerLottieSafe();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_entryController, _pulseController]),
          builder: (context, child) {
            final scale = _entryScale.value * (_entryController.isCompleted ? _pulseScale.value : 1);
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: SizedBox(
            width: 100,
            height: 100,
            child: FutureBuilder<LottieComposition?>(
              future: _compositionFuture,
              builder: (context, snapshot) {
                final composition = snapshot.data;
                if (!snapshot.hasError && composition != null) {
                  return Lottie(
                    composition: composition,
                    fit: BoxFit.contain,
                    repeat: true,
                  );
                }
                return Icon(
                  Icons.emoji_events,
                  size: 64,
                  color: AppColors.matchPotGold,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
