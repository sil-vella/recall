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

/// Immutable payload for the game-ended modal only. The modal subtree must use **only**
/// this object — never [StateManager] — so later WS/state merges cannot change the UI.
class GameEndedModalData {
  const GameEndedModalData({
    required this.title,
    required this.content,
    required this.messageType,
    required this.showCloseButton,
    required this.autoClose,
    required this.autoCloseDelay,
    required this.orderedWinners,
    required this.isCurrentUserWinner,
    this.userStats,
    required this.currentUserId,
  });

  final String title;
  final String content;
  final String messageType;
  final bool showCloseButton;
  final bool autoClose;
  final int autoCloseDelay;
  /// Deep-copied rows from `game_state.winners` at capture time.
  final List<Map<String, dynamic>> orderedWinners;
  final bool isCurrentUserWinner;
  final Map<String, dynamic>? userStats;
  /// Captured once with the snapshot (for "You" labels); not read from globals in the modal.
  final String currentUserId;

  /// Single read from [dutchGameState] when scheduling the modal — not used during modal build.
  static GameEndedModalData? fromDutchStateOnce(Map<String, dynamic> dutchGameState) {
    final messagesData = dutchGameState['messages'] as Map<String, dynamic>? ?? {};
    final isVisible = messagesData['isVisible'] == true;
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? '';
    if (!isVisible || gamePhase != 'game_ended') return null;

    final title = messagesData['title']?.toString() ?? 'Game Message';
    final content = messagesData['content']?.toString() ?? '';
    final messageType = messagesData['type']?.toString() ?? 'info';
    final showCloseButton = messagesData['showCloseButton'] ?? true;
    final autoClose = messagesData['autoClose'] ?? false;
    final autoCloseDelay = messagesData['autoCloseDelay'] as int? ?? 3000;
    final isCurrentUserWinner = messagesData['isCurrentUserWinner'] == true;

    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>?;
    final gameData = currentGame?['gameData'] as Map<String, dynamic>?;
    final gameState = gameData?['game_state'] as Map<String, dynamic>?;
    final orderedWinnersRaw = gameState?['winners'] as List<dynamic>?;
    final hasOrderedWinners = orderedWinnersRaw != null && orderedWinnersRaw.isNotEmpty;
    if (!hasOrderedWinners && content.isEmpty) return null;

    final deepWinners = <Map<String, dynamic>>[];
    if (orderedWinnersRaw != null) {
      for (final e in orderedWinnersRaw) {
        if (e is Map<String, dynamic>) {
          deepWinners.add(Map<String, dynamic>.from(e));
        } else if (e is Map) {
          deepWinners.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    final rawStats = dutchGameState['userStats'] as Map<String, dynamic>?;
    final userStats = rawStats == null ? null : Map<String, dynamic>.from(rawStats);
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();

    return GameEndedModalData(
      title: title,
      content: content,
      messageType: messageType,
      showCloseButton: showCloseButton,
      autoClose: autoClose,
      autoCloseDelay: autoCloseDelay,
      orderedWinners: deepWinners,
      isCurrentUserWinner: isCurrentUserWinner,
      userStats: userStats,
      currentUserId: currentUserId,
    );
  }
}

// --- Modal styling helpers (no [StateManager]) ---

Color _modalMessageTypeColor(String messageType) {
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

IconData _modalMessageTypeIcon(String messageType) {
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

Widget _modalStatChip(IconData icon, String label, String value, Color color) {
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

/// Ordered standings — uses only [orderedWinners] and [currentUserId] from [GameEndedModalData].
Widget _gameEndedOrderedWinnersColumn(
  List<Map<String, dynamic>> orderedWinners,
  String currentUserId,
) {
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
      case 'last_player':
        return 'Last Player';
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
            final playerId = e['playerId']?.toString() ?? '';
            final name = e['playerName']?.toString() ?? 'Unknown';
            final winType = e['winType'];
            final points = e['points'] as int?;
            final cardCount = e['cardCount'] as int?;
            final isWinner = winType != null && winType.toString().isNotEmpty;
            final isCurrentUser = currentUserId.isNotEmpty && playerId == currentUserId;
            final displayName = isCurrentUser ? 'You' : name;
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
                          ? ' — $points pts, $cardCount cards'
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

Widget _gameEndedUserStatsRow(Map<String, dynamic> userStats) {
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
        _modalStatChip(Icons.emoji_events, 'Wins', wins.toString(), AppColors.successColor),
        _modalStatChip(Icons.trending_down, 'Losses', losses.toString(), AppColors.errorColor),
        _modalStatChip(Icons.handshake, 'Draws', draws.toString(), AppColors.textSecondary),
        _modalStatChip(Icons.monetization_on, 'Coins', coins.toString(), AppColors.matchPotGold),
      ],
    ),
  );
}

/// Game-ended overlay: **only** [GameEndedModalData] — no reads from [StateManager].
class _GameEndedModalLayer extends StatefulWidget {
  const _GameEndedModalLayer({
    required this.data,
    required this.onClose,
  });

  final GameEndedModalData data;
  final VoidCallback onClose;

  @override
  State<_GameEndedModalLayer> createState() => _GameEndedModalLayerState();
}

class _GameEndedModalLayerState extends State<_GameEndedModalLayer> {
  @override
  void initState() {
    super.initState();
    if (widget.data.autoClose) {
      Future<void>.delayed(Duration(milliseconds: widget.data.autoCloseDelay), () {
        if (mounted) widget.onClose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final messageTypeColor = _modalMessageTypeColor(d.messageType);
    final headerBackgroundColor = Color.lerp(
          AppColors.widgetContainerBackground,
          messageTypeColor,
          0.15,
        ) ??
        AppColors.widgetContainerBackground;
    final headerTextColor = ThemeConfig.getTextColorForBackground(headerBackgroundColor);
    final hasRows = d.orderedWinners.isNotEmpty;

    return Material(
      color: AppColors.black.withValues(alpha: 0.54),
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
                      _modalMessageTypeIcon(d.messageType),
                      color: messageTypeColor,
                      size: 24,
                    ),
                    SizedBox(width: AppPadding.smallPadding.left),
                    Expanded(
                      child: Text(
                        d.title,
                        style: AppTextStyles.headingSmall().copyWith(
                          color: headerTextColor,
                        ),
                      ),
                    ),
                    if (d.showCloseButton)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close,
                          color: headerTextColor,
                        ),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),
              if (hasRows && d.isCurrentUserWinner) _WinnerTrophyInModal(),
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: hasRows
                      ? _gameEndedOrderedWinnersColumn(d.orderedWinners, d.currentUserId)
                      : Text(
                          d.content,
                          style: AppTextStyles.bodyMedium().copyWith(
                            color: AppColors.white,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              if (hasRows && d.userStats != null) _gameEndedUserStatsRow(d.userStats!),
              if (d.showCloseButton)
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
                        onPressed: widget.onClose,
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
  }
}

/// Non-game-ended messages (e.g. match start) — plain title/body from caller.
class _GenericMessageModalLayer extends StatefulWidget {
  const _GenericMessageModalLayer({
    required this.title,
    required this.content,
    required this.messageType,
    required this.showCloseButton,
    required this.autoClose,
    required this.autoCloseDelay,
    required this.onClose,
  });

  final String title;
  final String content;
  final String messageType;
  final bool showCloseButton;
  final bool autoClose;
  final int autoCloseDelay;
  final VoidCallback onClose;

  @override
  State<_GenericMessageModalLayer> createState() => _GenericMessageModalLayerState();
}

class _GenericMessageModalLayerState extends State<_GenericMessageModalLayer> {
  @override
  void initState() {
    super.initState();
    if (widget.autoClose) {
      Future<void>.delayed(Duration(milliseconds: widget.autoCloseDelay), () {
        if (mounted) widget.onClose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messageTypeColor = _modalMessageTypeColor(widget.messageType);
    final headerBackgroundColor = Color.lerp(
          AppColors.widgetContainerBackground,
          messageTypeColor,
          0.15,
        ) ??
        AppColors.widgetContainerBackground;
    final headerTextColor = ThemeConfig.getTextColorForBackground(headerBackgroundColor);

    return Material(
      color: AppColors.black.withValues(alpha: 0.54),
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
                      _modalMessageTypeIcon(widget.messageType),
                      color: messageTypeColor,
                      size: 24,
                    ),
                    SizedBox(width: AppPadding.smallPadding.left),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: AppTextStyles.headingSmall().copyWith(
                          color: headerTextColor,
                        ),
                      ),
                    ),
                    if (widget.showCloseButton)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close,
                          color: headerTextColor,
                        ),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: Text(
                    widget.content,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.white,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (widget.showCloseButton)
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
                        onPressed: widget.onClose,
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
  }
}

/// Messages Widget for Dutch Game
///
/// This widget displays game messages as a modal overlay.
/// It's hidden by default and only shows when messages are triggered.
/// Used for match notifications like "Match Starting", "Match Over", "Winner", "Points", etc.
///
/// Game-ended modal: [GameEndedModalData] is captured once from state; the modal subtree
/// is built only from that immutable object (no live [StateManager] reads).
class MessagesWidget extends StatefulWidget {
  const MessagesWidget({Key? key}) : super(key: key);

  @override
  State<MessagesWidget> createState() => _MessagesWidgetState();
}

class _MessagesWidgetState extends State<MessagesWidget> {
  static const bool LOGGING_SWITCH = false; // Enabled for winner modal debugging
  static final Logger _logger = Logger();

  /// Immutable snapshot — modal UI reads only this, never live state.
  GameEndedModalData? _gameEndedData;
  bool _snapshotSchedulePending = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final messagesData = dutchGameState['messages'] as Map<String, dynamic>? ?? {};
        final isVisible = messagesData['isVisible'] == true;
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? '';

        if (_gameEndedData != null) {
          if (gamePhase != 'game_ended' || !isVisible) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _gameEndedData = null;
                _snapshotSchedulePending = false;
              });
            });
            return const SizedBox.shrink();
          }
          return _GameEndedModalLayer(
            data: _gameEndedData!,
            onClose: () => _closeMessage(context),
          );
        }

        if (isVisible && gamePhase == 'game_ended') {
          final content = messagesData['content']?.toString() ?? '';
          final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
          final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
          final currentGame = games[currentGameId] as Map<String, dynamic>?;
          final gameData = currentGame?['gameData'] as Map<String, dynamic>?;
          final gameState = gameData?['game_state'] as Map<String, dynamic>?;
          final orderedWinners = gameState?['winners'] as List<dynamic>?;
          final hasOrderedWinners = orderedWinners != null && orderedWinners.isNotEmpty;
          if (!hasOrderedWinners && content.isEmpty) {
            return const SizedBox.shrink();
          }

          if (!_snapshotSchedulePending) {
            _snapshotSchedulePending = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final snap = GameEndedModalData.fromDutchStateOnce(
                StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {},
              );
              if (snap != null) {
                setState(() {
                  _gameEndedData = snap;
                  _snapshotSchedulePending = false;
                });
              } else {
                setState(() {
                  _snapshotSchedulePending = false;
                });
              }
            });
          }
          return const SizedBox.shrink();
        }

        if (!isVisible) {
          return const SizedBox.shrink();
        }

        final title = messagesData['title']?.toString() ?? 'Game Message';
        final content = messagesData['content']?.toString() ?? '';
        final messageType = messagesData['type']?.toString() ?? 'info';
        final showCloseButton = messagesData['showCloseButton'] ?? true;
        final autoClose = messagesData['autoClose'] ?? false;
        final autoCloseDelay = messagesData['autoCloseDelay'] ?? 3000;

        if (LOGGING_SWITCH) {
          final contentPreview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
          _logger.info('📬 MessagesWidget: Non-game-ended modal - title="$title", content="$contentPreview"');
        }

        return _GenericMessageModalLayer(
          title: title,
          content: content,
          messageType: messageType,
          showCloseButton: showCloseButton,
          autoClose: autoClose,
          autoCloseDelay: autoCloseDelay,
          onClose: () => _closeMessage(context),
        );
      },
    );
  }

  void _closeMessage(BuildContext context) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('MessagesWidget: Closing message modal');
      }

      final wasGameEnded = _gameEndedData != null ||
          StateManager().getModuleState<Map<String, dynamic>>('dutch_game')?['gamePhase']?.toString() ==
              'game_ended';

      setState(() {
        _gameEndedData = null;
        _snapshotSchedulePending = false;
      });

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
