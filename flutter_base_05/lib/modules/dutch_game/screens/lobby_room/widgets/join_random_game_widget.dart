import 'package:flutter/material.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../utils/dutch_game_helpers.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../backend_core/utils/level_matcher.dart';
import '../../../widgets/table_tier_felt_panel.dart';

// Enable for random game join debugging (logs to console / server.log)
const bool LOGGING_SWITCH = false; // Lobby random join UI → WS (enable-logging-switch.mdc)

/// Cover graphic over table-tier felt on the Quick Join panel.
const String _kJoinRandomTableBackGraphicAsset =
    'assets/images/backgrounds/home-table-backgraphic.png';

/// First unlocked table tier for the current user (join default).
int joinRandomDefaultTableLevel() {
  final stats = DutchGameHelpers.getUserDutchGameStats();
  final raw = stats?['level'];
  final userLevel = raw is int
      ? raw
      : raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 1;
  final unlocked = LevelMatcher.levelOrder.where((level) {
    final required = LevelMatcher.tableLevelToRequiredUserLevel(
      level,
      defaultLevel: level,
    );
    return userLevel >= required;
  }).toList();
  if (unlocked.isNotEmpty) return unlocked.first;
  return LevelMatcher.levelOrder.first;
}

/// Carousel table picker — same interaction model as home [FeatureSlot] carousel (PageView + arrows).
class _JoinRandomTableCarousel extends StatefulWidget {
  final int selectedLevel;
  final ValueChanged<int> onLevelChanged;
  final ValueChanged<int>? onDisplayLevelChanged;
  final bool lockedInteraction;

  const _JoinRandomTableCarousel({
    required this.selectedLevel,
    required this.onLevelChanged,
    this.onDisplayLevelChanged,
    required this.lockedInteraction,
  });

  @override
  State<_JoinRandomTableCarousel> createState() => _JoinRandomTableCarouselState();
}

class _JoinRandomTableCarouselState extends State<_JoinRandomTableCarousel> {
  late PageController _pageController;
  int _pageIndex = 0;
  bool _programmaticPage = false;

  @override
  void initState() {
    super.initState();
    final levels = LevelMatcher.levelOrder;
    final initial = levels.contains(widget.selectedLevel)
        ? levels.indexOf(widget.selectedLevel)
        : 0;
    _pageIndex = initial;
    _pageController = PageController(
      initialPage: initial,
      viewportFraction: 0.82,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || levels.isEmpty) return;
      widget.onDisplayLevelChanged?.call(levels[_pageIndex]);
    });
  }

  @override
  void didUpdateWidget(covariant _JoinRandomTableCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLevel != widget.selectedLevel &&
        LevelMatcher.levelOrder.contains(widget.selectedLevel)) {
      final idx = LevelMatcher.levelOrder.indexOf(widget.selectedLevel);
      if (idx >= 0 && idx != _pageIndex && _pageController.hasClients) {
        _programmaticPage = true;
        _pageController
            .animateToPage(
          idx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        )
            .then((_) {
          if (mounted) _programmaticPage = false;
        });
        _pageIndex = idx;
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isLevelLocked(int level) {
    final required = LevelMatcher.tableLevelToRequiredUserLevel(
      level,
      defaultLevel: level,
    );
    final userLevel = _readUserLevel();
    return userLevel < required;
  }

  static int _readUserLevel() {
    final stats = DutchGameHelpers.getUserDutchGameStats();
    final raw = stats?['level'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 1;
  }

  void _onPageChanged(int index) {
    if (_programmaticPage) return;
    final levels = LevelMatcher.levelOrder;
    if (index < 0 || index >= levels.length) return;
    final level = levels[index];
    setState(() => _pageIndex = index);
    widget.onDisplayLevelChanged?.call(level);
    if (!_isLevelLocked(level)) {
      widget.onLevelChanged(level);
    }
  }

  void _prev() {
    final levels = LevelMatcher.levelOrder;
    if (_pageIndex <= 0) return;
    if (_isLevelLocked(levels[_pageIndex - 1])) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    final levels = LevelMatcher.levelOrder;
    if (_pageIndex >= levels.length - 1) return;
    if (_isLevelLocked(levels[_pageIndex + 1])) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final levels = LevelMatcher.levelOrder;
    if (levels.isEmpty) return const SizedBox.shrink();

    const carouselHeight = 120.0;
    final hasPrevPage = _pageIndex > 0;
    final hasNextPage = _pageIndex < levels.length - 1;
    final arrowPrevEnabled =
        hasPrevPage && !_isLevelLocked(levels[_pageIndex - 1]);
    final arrowNextEnabled =
        hasNextPage && !_isLevelLocked(levels[_pageIndex + 1]);

    return Semantics(
      label: 'join_random_table_carousel',
      identifier: 'join_random_table_carousel',
      child: SizedBox(
        height: carouselHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PageView.builder(
              controller: _pageController,
              physics: widget.lockedInteraction
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemCount: levels.length,
              itemBuilder: (context, index) {
                final level = levels[index];
                final locked = _isLevelLocked(level);
                final title = LevelMatcher.levelToTitle(level);
                final fee = LevelMatcher.levelToCoinFee(level);
                return AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    double opacity = 0.55;
                    if (_pageController.position.haveDimensions) {
                      final page = _pageController.page ?? _pageController.initialPage.toDouble();
                      final distance = (page - index).abs();
                      if (distance < 0.5) {
                        opacity = 1.0 - (distance * 0.9);
                        opacity = opacity.clamp(0.55, 1.0);
                      } else {
                        opacity = 0.55;
                      }
                    } else {
                      opacity = index == _pageIndex ? 1.0 : 0.55;
                    }
                    return Opacity(
                      opacity: locked ? opacity * 0.65 : opacity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Text(
                                  title,
                                  style: AppTextStyles.bodyMedium().copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (locked)
                                  Icon(
                                    Icons.lock_outline,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                              ],
                            ),
                            SizedBox(height: AppPadding.smallPadding.top * 0.5),
                            Text(
                              '${fee}c',
                              style: AppTextStyles.label().copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            if (hasPrevPage && !widget.lockedInteraction)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: arrowPrevEnabled ? 1.0 : 0.4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: arrowPrevEnabled ? _prev : null,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.accentColor.withValues(alpha: 0.45),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            size: 16,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (hasNextPage && !widget.lockedInteraction)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: arrowNextEnabled ? 1.0 : 0.4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: arrowNextEnabled ? _next : null,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.accentColor.withValues(alpha: 0.45),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
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
  /// Carousel page tier (including locked preview) — drives inner panel felt styling.
  int _displayTableLevel = LevelMatcher.levelOrder.first;
  static final Logger _logger = Logger();

  int _firstUnlockedTableLevel() => joinRandomDefaultTableLevel();

  @override
  void initState() {
    super.initState();
    final initial = _firstUnlockedTableLevel();
    _selectedTableLevel = initial;
    _displayTableLevel = initial;
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    // Listen for join room errors from backend
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.on('join_room_error', (data) {
      if (mounted) {
        final error = data['message'] ?? data['error'] ?? 'Unknown error';
        final errStr = error.toString().toLowerCase();
        final skipSnack = errStr.contains('insufficient coins');
        if (!skipSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Join random game failed: $error'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
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
    final safeLevel = LevelMatcher.levelOrder.contains(_selectedTableLevel)
        ? _selectedTableLevel
        : _firstUnlockedTableLevel();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
        child: Stack(
          children: [
            Positioned.fill(
              child: TableTierFeltPanel(tableLevel: _displayTableLevel),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.3,
                  child: Image.asset(
                    _kJoinRandomTableBackGraphicAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Padding(
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
            _JoinRandomTableCarousel(
              selectedLevel: safeLevel,
              lockedInteraction: _isLoading,
              onDisplayLevelChanged: (level) {
                setState(() => _displayTableLevel = level);
              },
              onLevelChanged: _isLoading
                  ? (_) {}
                  : (level) {
                      setState(() => _selectedTableLevel = level);
                    },
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
          ],
        ),
      ),
    );
  }
}
