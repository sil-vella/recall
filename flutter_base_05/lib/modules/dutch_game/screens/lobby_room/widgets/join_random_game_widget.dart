import 'package:flutter/material.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../utils/dutch_game_helpers.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../backend_core/utils/level_matcher.dart';
import '../../../utils/dutch_game_play_table_style_mapping.dart';
import '../../../widgets/table_tier_felt_panel.dart';

// Enable for random game join debugging (logs to console / server.log)
const bool LOGGING_SWITCH = false; // Lobby random join UI → WS (enable-logging-switch.mdc; set false after test)

/// User progression level from cached Dutch stats (used for tier / event gates).
int joinRandomReadUserLevel() {
  final stats = DutchGameHelpers.getUserDutchGameStats();
  final raw = stats?['level'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 1;
}

/// Highest unlocked **standard** table tier (`game_level`) — Quick Join carousel default landing.
int joinRandomHighestUnlockedTableLevel() {
  LevelMatcher.ensureHydratedMinimal();
  final userLevel = joinRandomReadUserLevel();
  final unlocked = LevelMatcher.levelOrder.where((level) {
    final required = LevelMatcher.tableLevelToRequiredUserLevel(
      level,
      defaultLevel: level,
    );
    return userLevel >= required;
  }).toList();
  if (unlocked.isEmpty) {
    return LevelMatcher.levelOrder.isNotEmpty ? LevelMatcher.levelOrder.first : 1;
  }
  return unlocked.reduce((a, b) => a > b ? a : b);
}

/// Carousel row: special event (`special_events`) or standard tier.
abstract class JoinRandomCarouselEntry {}

class JoinRandomTierEntry extends JoinRandomCarouselEntry {
  JoinRandomTierEntry(this.level);

  final int level;
}

class JoinRandomEventEntry extends JoinRandomCarouselEntry {
  JoinRandomEventEntry(this.raw);

  final Map<String, dynamic> raw;

  String get id => (raw['id'] ?? raw['event_id'] ?? '').toString();
}

/// `game_level` used for WS join; optional special-event payload for visuals.
class JoinRandomSelection {
  JoinRandomSelection({this.specialEvent, required this.gameLevel});

  /// Non-null when the carousel is on a `special_events` item.
  final Map<String, dynamic>? specialEvent;
  final int gameLevel;

  bool get isSpecialEvent => specialEvent != null;
}

JoinRandomSelection joinRandomSelectionForEntry(JoinRandomCarouselEntry e) {
  if (e is JoinRandomTierEntry) {
    return JoinRandomSelection(specialEvent: null, gameLevel: e.level);
  }
  if (e is JoinRandomEventEntry) {
    return JoinRandomSelection(
      specialEvent: e.raw,
      gameLevel: resolvedGameLevelForSpecialEvent(e.raw),
    );
  }
  throw StateError('Unknown JoinRandomCarouselEntry');
}

/// Resolves WS `game_level` for a catalog special event (`game_level` field, else coin_fee tier match).
int resolvedGameLevelForSpecialEvent(Map<String, dynamic> raw) {
  LevelMatcher.ensureHydratedMinimal();
  final gl = raw['game_level'];
  final glInt = gl is int ? gl : int.tryParse('$gl');
  if (glInt != null &&
      glInt >= 1 &&
      LevelMatcher.isValidLevel(glInt)) {
    return glInt;
  }
  final cf = raw['coin_fee'];
  final fee = cf is int ? cf : int.tryParse('$cf');
  if (fee != null && fee >= 0) {
    for (final lvl in LevelMatcher.levelOrder) {
      if (LevelMatcher.levelToCoinFee(lvl) == fee) return lvl;
    }
  }
  return LevelMatcher.levelOrder.isNotEmpty ? LevelMatcher.levelOrder.first : 1;
}

List<JoinRandomCarouselEntry> buildJoinRandomCarouselEntries() {
  LevelMatcher.ensureHydratedMinimal();
  final eventsReversed =
      LevelMatcher.specialEvents.map((m) => Map<String, dynamic>.from(m)).toList().reversed;
  final out = <JoinRandomCarouselEntry>[
    ...eventsReversed.map(JoinRandomEventEntry.new),
    ...LevelMatcher.levelOrder.map((l) => JoinRandomTierEntry(l)),
  ];
  return out;
}

/// Page index aligned with **[special_events reversed] + [tiers]** — lands on highest unlocked tier.
int defaultCarouselIndexForHighestUnlockedTier(List<JoinRandomCarouselEntry> entries) {
  final best = joinRandomHighestUnlockedTableLevel();
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e is JoinRandomTierEntry && e.level == best) return i;
  }
  return 0;
}

int joinRandomDisplayCoins(JoinRandomCarouselEntry e) {
  if (e is JoinRandomTierEntry) return LevelMatcher.levelToCoinFee(e.level);
  if (e is JoinRandomEventEntry) {
    final cf = e.raw['coin_fee'];
    final fee = cf is int ? cf : int.tryParse('$cf');
    if (fee != null && fee >= 0) return fee;
    return LevelMatcher.levelToCoinFee(resolvedGameLevelForSpecialEvent(e.raw));
  }
  return 0;
}

String joinRandomCarouselTitle(JoinRandomCarouselEntry e) {
  if (e is JoinRandomTierEntry) return LevelMatcher.levelToTitle(e.level);
  if (e is JoinRandomEventEntry) {
    final t = (e.raw['title'] ?? '').toString().trim();
    return t.isNotEmpty ? t : 'Event';
  }
  return '';
}

bool joinRandomEntryLocked(JoinRandomCarouselEntry e) {
  final userLevel = joinRandomReadUserLevel();
  if (e is JoinRandomTierEntry) {
    final required = LevelMatcher.tableLevelToRequiredUserLevel(
      e.level,
      defaultLevel: e.level,
    );
    return userLevel < required;
  }
  if (e is JoinRandomEventEntry) {
    final minU = e.raw['min_user_level'];
    final req = minU is int ? minU : int.tryParse('$minU');
    if (req == null || req < 1) return false;
    return userLevel < req;
  }
  return true;
}

int? joinRandomRequiredPlayerLevel(JoinRandomCarouselEntry e) {
  if (e is JoinRandomTierEntry) {
    return LevelMatcher.tableLevelToRequiredUserLevel(e.level, defaultLevel: e.level);
  }
  if (e is JoinRandomEventEntry) {
    final minU = e.raw['min_user_level'];
    final req = minU is int ? minU : int.tryParse('$minU');
    if (req == null || req < 1) return null;
    return req;
  }
  return null;
}

/// Carousel table picker — [special_events] reversed, then tiers in catalog order.
class _JoinRandomTableCarousel extends StatefulWidget {
  final List<JoinRandomCarouselEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onPageIndexChanged;
  final bool lockedInteraction;

  const _JoinRandomTableCarousel({
    required this.entries,
    required this.selectedIndex,
    required this.onPageIndexChanged,
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
    final n = widget.entries.length;
    final initial = n == 0
        ? 0
        : widget.selectedIndex.clamp(0, n - 1);
    _pageIndex = initial;
    _pageController = PageController(
      initialPage: initial,
      viewportFraction: 0.82,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.entries.isEmpty) return;
      widget.onPageIndexChanged(_pageIndex);
    });
  }

  @override
  void didUpdateWidget(covariant _JoinRandomTableCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entriesChanged = oldWidget.entries.length != widget.entries.length ||
        !identical(oldWidget.entries, widget.entries);
    if (widget.entries.isEmpty || !_pageController.hasClients) {
      return;
    }
    final n = widget.entries.length;
    final idx = widget.selectedIndex.clamp(0, n - 1);
    final indexOutOfRange = _pageIndex > n - 1;

    // When catalog length/content changes, sync page explicitly (jump avoids PageView drift).
    if (entriesChanged || indexOutOfRange) {
      _programmaticPage = true;
      _pageController.jumpToPage(idx);
      _programmaticPage = false;
      _pageIndex = idx;
      return;
    }
    if (oldWidget.selectedIndex != widget.selectedIndex && idx >= 0 && idx != _pageIndex) {
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (_programmaticPage) return;
    final levels = widget.entries;
    if (index < 0 || index >= levels.length) return;
    setState(() => _pageIndex = index);
    widget.onPageIndexChanged(index);
  }

  void _prev() {
    if (_pageIndex <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    final n = widget.entries.length;
    if (_pageIndex >= n - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();

    /// Room for centered lock + two text lines in carousel when tier is locked.
    const carouselHeight = 140.0;
    const lockedTierIconSize = 48.0;
    final hasPrevPage = _pageIndex > 0;
    final hasNextPage = _pageIndex < entries.length - 1;

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
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final locked = joinRandomEntryLocked(entry);
                final title = joinRandomCarouselTitle(entry);
                final fee = joinRandomDisplayCoins(entry);
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
                            if (entry is JoinRandomEventEntry) ...[
                              Text(
                                'EVENT',
                                style: AppTextStyles.caption().copyWith(
                                  color: AppColors.accentColor,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: AppPadding.smallPadding.top * 0.35),
                            ],
                            if (locked) ...[
                              Icon(
                                Icons.lock_outline,
                                size: lockedTierIconSize,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(height: AppPadding.smallPadding.top * 0.75),
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
                              SizedBox(height: AppPadding.smallPadding.top * 0.5),
                              Text(
                                '${fee}c',
                                style: AppTextStyles.label().copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ] else ...[
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
                              SizedBox(height: AppPadding.smallPadding.top * 0.5),
                              Text(
                                '${fee}c',
                                style: AppTextStyles.label().copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
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
                    opacity: hasPrevPage ? 1.0 : 0.4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: hasPrevPage ? _prev : null,
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
                    opacity: hasNextPage ? 1.0 : 0.4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: hasNextPage ? _next : null,
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
  late List<JoinRandomCarouselEntry> _entries;
  late int _carouselIndex;
  static final Logger _logger = Logger();

  /// Carousel identity for resync after [LevelMatcher] catalog merge.
  static String? _carouselEntryKey(JoinRandomCarouselEntry e) {
    if (e is JoinRandomTierEntry) return 't:${e.level}';
    if (e is JoinRandomEventEntry) return 'e:${e.id}';
    return null;
  }

  void _resyncCarouselFromCatalog() {
    final anchor = _entries.isEmpty
        ? null
        : _carouselEntryKey(
            _entries[_carouselIndex.clamp(0, _entries.length - 1)],
          );
    final next = buildJoinRandomCarouselEntries();
    var idx = defaultCarouselIndexForHighestUnlockedTier(next);
    if (anchor != null) {
      for (var i = 0; i < next.length; i++) {
        if (_carouselEntryKey(next[i]) == anchor) {
          idx = i;
          break;
        }
      }
    }
    _entries = next;
    _carouselIndex = next.isEmpty ? 0 : idx.clamp(0, next.length - 1);
  }

  void _onCatalogMerged() {
    if (!mounted) return;
    _resyncCarouselFromCatalog();
    setState(() {});
  }

  JoinRandomCarouselEntry get _currentEntry =>
      _entries.isEmpty ? JoinRandomTierEntry(1) : _entries[_carouselIndex.clamp(0, _entries.length - 1)];

  JoinRandomSelection get _selection => joinRandomSelectionForEntry(_currentEntry);

  @override
  void initState() {
    super.initState();
    LevelMatcher.ensureHydratedMinimal();
    _entries = buildJoinRandomCarouselEntries();
    _carouselIndex = defaultCarouselIndexForHighestUnlockedTier(_entries);
    if (_entries.isEmpty) {
      _carouselIndex = 0;
    } else {
      _carouselIndex = _carouselIndex.clamp(0, _entries.length - 1);
    }
    LevelMatcher.catalogChangeVersion.addListener(_onCatalogMerged);
    _setupWebSocketListeners();
  }

  bool _isCurrentLocked() => joinRandomEntryLocked(_currentEntry);

  void _onJoinRoomError(dynamic data) {
    if (mounted) {
      final map =
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final error = map['message'] ?? map['error'] ?? 'Unknown error';
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
  }

  void _setupWebSocketListeners() {
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.on('join_room_error', _onJoinRoomError);
  }

  @override
  void dispose() {
    LevelMatcher.catalogChangeVersion.removeListener(_onCatalogMerged);
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.off('join_room_error', _onJoinRoomError);
    super.dispose();
  }

  Future<void> _handleJoinRandomGame({required bool isClearAndCollect}) async {
    if (_isLoading) return;
    if (LOGGING_SWITCH) {
      _logger.info('🎯 JoinRandomGame: button pressed (isClearAndCollect=$isClearAndCollect)', isOn: true);
    }

    if (_isCurrentLocked()) {
      if (mounted) {
        final req = joinRandomRequiredPlayerLevel(_currentEntry);
        final msg = req != null
            ? 'This option is locked. Reach player level $req to play here, or swipe to an unlocked table.'
            : 'This option is locked. Swipe to an unlocked table.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg,
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.warningColor,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final isReady = await DutchGameHelpers.ensureWebSocketReady();
      if (LOGGING_SWITCH) {
        _logger.info('🎯 JoinRandomGame: WebSocket ready=$isReady', isOn: true);
      }
      if (!isReady) {
        return;
      }

      final gameLevel = _selection.gameLevel;
      final specialEventRaw = _selection.specialEvent;
      final specialEventId = _selection.isSpecialEvent &&
              specialEventRaw != null
          ? (specialEventRaw['id'] ?? specialEventRaw['event_id'])?.toString().trim()
          : null;
      final result = await DutchGameHelpers.joinRandomGame(
        isClearAndCollect: isClearAndCollect,
        gameLevel: gameLevel,
        specialEventId:
            specialEventId != null && specialEventId.isNotEmpty ? specialEventId : null,
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

  Widget _buildBackdrop() {
    final e = _currentEntry;
    if (e is JoinRandomEventEntry) {
      final gl = resolvedGameLevelForSpecialEvent(e.raw);
      final st = e.raw['style'];
      final styleMap =
          st is Map ? Map<String, dynamic>.from(st) : <String, dynamic>{};
      return DutchGamePlayTableStyles.tableBackGraphicFillForSpecialEvent(
        eventId: e.id,
        styleMap: styleMap,
        fallbackTableLevel: gl,
      );
    }
    if (e is JoinRandomTierEntry) {
      return DutchGamePlayTableStyles.tableBackGraphicFill(e.level);
    }
    return DutchGamePlayTableStyles.tableBackGraphicFill(1);
  }

  Widget _buildFeltOverlay() {
    final e = _currentEntry;
    if (e is JoinRandomEventEntry) {
      final gl = resolvedGameLevelForSpecialEvent(e.raw);
      final st = e.raw['style'];
      Color? feltO;
      Color? spotO;
      if (st is Map) {
        feltO = dutchHexToColor(st['felt_hex']?.toString());
        spotO = dutchHexToColor(st['spotlight_hex']?.toString());
      }
      return TableTierFeltPanel(
        tableLevel: gl,
        feltOverride: feltO,
        spotlightOverride: spotO,
      );
    }
    if (e is JoinRandomTierEntry) {
      return TableTierFeltPanel(tableLevel: e.level);
    }
    return const TableTierFeltPanel(tableLevel: 1);
  }

  @override
  Widget build(BuildContext context) {
    final tableLocked = _isCurrentLocked();
    final reqLevel = joinRandomRequiredPlayerLevel(_currentEntry);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: _buildBackdrop(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.7,
                  child: _buildFeltOverlay(),
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
                    entries: _entries,
                    selectedIndex: _carouselIndex,
                    lockedInteraction: _isLoading,
                    onPageIndexChanged: (i) {
                      setState(() => _carouselIndex = i);
                    },
                  ),
                  if (tableLocked) ...[
                    SizedBox(height: AppPadding.smallPadding.top),
                    Semantics(
                      label: 'join_random_table_locked_notice',
                      identifier: 'join_random_table_locked_notice',
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          reqLevel != null
                              ? 'This option is locked for your account. Reach player level $reqLevel to play here, or swipe to an unlocked table.'
                              : 'This option is locked. Swipe to an unlocked table or event.',
                          style: AppTextStyles.caption().copyWith(
                            color: AppColors.warningColor,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: AppPadding.defaultPadding.top),
                  Text(
                    'Select Game Type',
                    style: AppTextStyles.label().copyWith(
                      color: AppColors.white,
                    ),
                  ),
                  SizedBox(height: AppPadding.smallPadding.top),
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
                            : const Icon(Icons.shuffle, size: AppSizes.iconSmall),
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
                            : const Icon(Icons.casino, size: AppSizes.iconSmall),
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
