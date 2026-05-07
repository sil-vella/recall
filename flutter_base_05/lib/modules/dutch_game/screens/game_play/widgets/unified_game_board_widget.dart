import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../widgets/dutch_slice_builder.dart';
import '../utils/dutch_anim_layout_reporter.dart';
import '../utils/dutch_anim_runtime.dart';
import '../utils/dutch_opponent_seat_layout.dart';
import 'dutch_card_anim_overlay.dart';
import 'player_status_chip_widget.dart';
import 'circular_timer_widget.dart';
import '../../../managers/player_action.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../dutch_game/managers/dutch_event_handler_callbacks.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../demo/demo_functionality.dart';
import '../../../utils/dutch_game_helpers.dart';

/// When true, logs layout overflow traces, pile debug, and rebuild timing for this widget.
const bool LOGGING_SWITCH = false; // enable-logging-switch.mdc; one switch per file

/// Profile + countdown ring in hand HUD: outer diameter, stroke, inner avatar (see [CircularTimerWidget]).
const double _kHudRingOuter = 34.0;
const double _kHudRingStroke = 3.0;
const double _kHudAvatarInRing = _kHudRingOuter - 2 * _kHudRingStroke - 2.0;

String _friendlyCardBackLabel(String cardBackId) {
  switch (cardBackId) {
    case 'card_back_ember':
      return 'Ember';
    case 'card_back_ocean':
      return 'Ocean';
    default:
      if (cardBackId.isEmpty) return 'Default';
      final base = cardBackId.replaceFirst('card_back_', '').replaceAll('_', ' ').trim();
      if (base.isEmpty) return 'Default';
      return base[0].toUpperCase() + base.substring(1);
  }
}

/// Where profile + timer HUD sits relative to **logical hand index 0** (slightly outside the card).
enum _HandHudCorner {
  myHandTopLeft,
  oppTopBottomRight,
  oppLeftTopRight,
  oppRightBottomLeft,
}

/// Stacks [hud] on [cardSlot] at the given corner, pushed outward by [outset].
Widget _stackHandHudOnFirstCardSlot({
  required Widget cardSlot,
  required _HandHudCorner corner,
  required Widget hud,
  double outset = 8,
}) {
  late final Widget positionedHud;
  switch (corner) {
    case _HandHudCorner.myHandTopLeft:
      positionedHud = Positioned(left: -outset, top: -outset, child: hud);
      break;
    case _HandHudCorner.oppTopBottomRight:
      positionedHud = Positioned(right: -outset, bottom: -outset, child: hud);
      break;
    case _HandHudCorner.oppLeftTopRight:
      positionedHud = Positioned(right: -outset, top: -outset, child: hud);
      break;
    case _HandHudCorner.oppRightBottomLeft:
      positionedHud = Positioned(left: -outset, bottom: -outset, child: hud);
      break;
  }
  return Stack(
    clipBehavior: Clip.none,
    children: [
      cardSlot,
      positionedHud,
    ],
  );
}

_HandHudCorner _handHudCornerForTableOrientation(CardTableOrientation o) {
  switch (o) {
    case CardTableOrientation.portraitUp:
      return _HandHudCorner.myHandTopLeft;
    case CardTableOrientation.portraitDown:
      return _HandHudCorner.oppTopBottomRight;
    case CardTableOrientation.landscapeFromLeft:
      return _HandHudCorner.oppLeftTopRight;
    case CardTableOrientation.landscapeFromRight:
      return _HandHudCorner.oppRightBottomLeft;
  }
}

/// Opponent slice + peek protection inputs for the play surface (top strip + middle row).
class _OppBoardContext {
  _OppBoardContext._({
    required this.cardsToPeek,
    required this.opponents,
    required this.currentTurnIndex,
    required this.isGameActive,
    required this.playerStatus,
  }) : buckets = bucketOpponentsForDutchTable(opponents);

  final List<dynamic> cardsToPeek;
  final List<dynamic> opponents;
  final int currentTurnIndex;
  final bool isGameActive;
  final String playerStatus;
  final ({List<Map<String, dynamic>> top, List<Map<String, dynamic>> left, List<Map<String, dynamic>> right}) buckets;
}

/// View model for [UnifiedGameBoardWidget]: no full [games] map so unrelated room/game
/// entries do not invalidate the subtree. Piles and [boardGameState] come from the current game only.
Map<String, dynamic> _unifiedBoardViewSlice(Map<String, dynamic> d) {
  final currentGameId = d['currentGameId']?.toString() ?? '';
  final games = d['games'] as Map<String, dynamic>? ?? {};
  final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
  final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
  final gs = gameData['game_state'] as Map<String, dynamic>? ?? {};
  final myHand = Map<String, dynamic>.from(d['myHand'] as Map? ?? {});

  Map<String, dynamic> currentPlayerMap = <String, dynamic>{};
  final cpRaw = d['currentPlayer'];
  if (cpRaw is Map<String, dynamic>) {
    currentPlayerMap = Map<String, dynamic>.from(cpRaw);
  }

  final timerConfigRaw = gs['timerConfig'] as Map<String, dynamic>?;
  final timerConfigForSlice = timerConfigRaw == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(timerConfigRaw);

  return {
    'currentGameId': currentGameId,
    'gamePhase': d['gamePhase']?.toString() ?? '',
    'isGameActive': d['isGameActive'] ?? false,
    'isMyTurn': d['isMyTurn'] ?? false,
    'myCardsToPeek': List<dynamic>.from(d['myCardsToPeek'] as List? ?? []),
    'protectedCardsToPeek': d['protectedCardsToPeek'] is List
        ? List<dynamic>.from(d['protectedCardsToPeek'] as List)
        : null,
    'myDrawnCard': Map<String, dynamic>.from(d['myDrawnCard'] as Map? ?? {}),
    'myHand': myHand,
    'centerBoard': Map<String, dynamic>.from(d['centerBoard'] as Map? ?? {}),
    'opponentsPanel': Map<String, dynamic>.from(d['opponentsPanel'] as Map? ?? {}),
    'drawPile': List<dynamic>.from(gs['drawPile'] as List? ?? []),
    'discardPile': List<dynamic>.from(gs['discardPile'] as List? ?? []),
    'boardGameState': <String, dynamic>{
      'phase': gs['phase'],
      'timerConfig': timerConfigForSlice,
      'finalRoundActive': gs['finalRoundActive'] ?? false,
      'finalRoundCalledBy': gs['finalRoundCalledBy']?.toString(),
      'players': List<dynamic>.from(gs['players'] as List? ?? []),
    },
    'userStats': Map<String, dynamic>.from(d['userStats'] as Map? ?? {}),
    'currentPlayer': currentPlayerMap,
    'playerStatus': d['playerStatus']?.toString() ?? myHand['playerStatus']?.toString() ?? 'unknown',
    'actionError': d['actionError'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(d['actionError'] as Map)
        : null,
  };
}

/// Unified play surface: top strip (intrinsic height, full width) → [Expanded] middle
/// row (left/right [Expanded], center board [IntrinsicWidth]) → my hand (intrinsic height).
/// Opponent bucketing: 1 → left only; 2 → left + top; 3+ indices 0/1/2… → left / top / right.
///
/// **Centering (layout):**
/// - **My-hand live card row:** horizontal centering uses a single mechanism in
///   [_buildMyHandCardsGrid] only (`Row` + adaptive card sizing to fit width; no horizontal scroll).
///   Other `Center`/`Align` widgets here are for opponents, piles, pot, or empty placeholders—not the my-hand row.
/// - **Opponents:** top strip uses `Center`+`Row` for the seat group; top `Wrap` uses `WrapAlignment.center`;
///   side columns use `Align(centerLeft/centerRight)`—each intentional for table UX.
/// - **Flight cards:** [DutchCardAnimOverlay] uses `Center` inside measured rects for geometry, not board row centering.
class UnifiedGameBoardWidget extends StatefulWidget {
  const UnifiedGameBoardWidget({Key? key}) : super(key: key);

  @override
  State<UnifiedGameBoardWidget> createState() => _UnifiedGameBoardWidgetState();
}

class _UnifiedGameBoardWidgetState extends State<UnifiedGameBoardWidget> with TickerProviderStateMixin {
  final Logger _logger = Logger();

  /// Rebuild count when this file's LOGGING_SWITCH is enabled.
  static int _unifiedWidgetRebuildCount = 0;
  
  // ========== Opponents Panel State ==========
  String? _clickedCardId;
  bool _isCardsToPeekProtected = false;
  List<dynamic>? _protectedCardsToPeek;
  Timer? _cardsToPeekProtectionTimer;
  
  // ========== Draw Pile State ==========
  String? _clickedPileType;
  AnimationController? _glowAnimationController;
  Animation<double>? _glowAnimation;
  
  // ========== Discard Pile State ==========
  // (No state needed - using _cardKeys for all cards)
  
  // ========== My Hand State ==========
  int _initialPeekSelectionCount = 0;
  List<String> _initialPeekSelectedCardIds = [];
  bool _isProcessingAction = false;
  /// True immediately when user taps "Call Final Round"; shows "Final Round Active" until state catches up.
  bool _callFinalRoundTappedPending = false;
  bool _isMyHandCardsToPeekProtected = false;
  List<dynamic>? _protectedMyHandCardsToPeek;
  Timer? _myHandCardsToPeekProtectionTimer;
  String? _previousPlayerStatus; // Track previous status to detect transitions
  /// Last [game_state.phase] seen — used to reset local flags on transition to `initial_peek` (rematch / new deal).
  String? _lastPhaseForLocalReset;

  /// Minimum card width when shrinking hands to fit layout (preserves [CardDimensions.CARD_ASPECT_RATIO]).
  static const double _kMinCardWidth = 20.0;

  /// Shrinks card width so [slots] cards fit in [availableWidth] (and optionally [availableHeight]).
  Size _adaptiveCardSize({
    required double availableWidth,
    required int slots,
    required double slotGap,
    double? availableHeight,
    bool verticalStack = false,
    double minWidth = _kMinCardWidth,
  }) {
    final n = slots <= 0 ? 1 : slots;
    if (verticalStack &&
        availableHeight != null &&
        availableHeight.isFinite &&
        availableHeight > 0) {
      final gapBudget = (n - 1) * slotGap;
      final maxTotalCardHeight = availableHeight - gapBudget;
      if (maxTotalCardHeight <= 0) {
        final w = _kMinCardWidth.clamp(_kMinCardWidth, CardDimensions.MAX_CARD_WIDTH);
        return Size(w, w / CardDimensions.CARD_ASPECT_RATIO);
      }
      final maxHPerCard = maxTotalCardHeight / n;
      var w = maxHPerCard * CardDimensions.CARD_ASPECT_RATIO;
      w = w.clamp(minWidth, CardDimensions.MAX_CARD_WIDTH);
      if (w > availableWidth) {
        w = availableWidth.clamp(minWidth, CardDimensions.MAX_CARD_WIDTH);
      }
      return Size(w, w / CardDimensions.CARD_ASPECT_RATIO);
    }

    if (verticalStack) {
      // For side stacks with unbounded height, do not divide by card count.
      // Start from max that fits column width and only shrink if height is constrained.
      final w = availableWidth.clamp(minWidth, CardDimensions.MAX_CARD_WIDTH);
      return Size(w, w / CardDimensions.CARD_ASPECT_RATIO);
    }

    // Keep one trailing gap budget because slot builders currently pad each card on the right.
    var w = (availableWidth - n * slotGap) / n;
    w = w.clamp(minWidth, CardDimensions.MAX_CARD_WIDTH);
    if (availableHeight != null && availableHeight.isFinite && availableHeight > 0) {
      final maxWByH = availableHeight * CardDimensions.CARD_ASPECT_RATIO;
      if (maxWByH < w) {
        w = maxWByH.clamp(minWidth, CardDimensions.MAX_CARD_WIDTH);
      }
    }
    return Size(w, w / CardDimensions.CARD_ASPECT_RATIO);
  }

  /// Timer to clear selected-card overlays (opponent highlight + my hand selection) after 3 seconds.
  Timer? _selectedCardOverlayTimer;
  bool _gameBoardHeightUpdateScheduled = false;
  double? _lastPublishedGameBoardHeight;
  
  // ========== Card Keys (for widget identification) ==========
  /// Map of cardId -> GlobalKey for all cards (reused across rebuilds)
  final Map<String, GlobalKey> _cardKeys = {};
  
  /// GlobalKey for game board section
  final GlobalKey _gameBoardKey = GlobalKey(debugLabel: 'game_board_section');
  
  /// GlobalKey for draw pile section
  final GlobalKey _drawPileKey = GlobalKey(debugLabel: 'draw_pile_section');
  
  /// GlobalKey for discard pile section
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'discard_pile_section');

  /// Anchor for anim rects ([DutchAnimRuntime] card positions / overlay are in this box's coordinates).
  final GlobalKey _animStackAnchorKey = GlobalKey(debugLabel: 'anim_stack_anchor');

  bool _animLayoutCommitScheduled = false;

  /// Avoid mergeLayout loops when layout post-frame runs repeatedly with same geometry.
  String? _lastAnimLayoutSignature;

  /// Dedupe [DutchAnimRuntime] notifies: mask and/or anim queue length (for my-hand row stability).
  String _lastAnimRuntimeStabilitySig = '';

  Map<String, dynamic> _dutchGameState() =>
      StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? const {};

  @override
  void initState() {
    super.initState();
    // Initialize glow animation controller
    _glowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowAnimationController!,
      curve: Curves.easeInOut,
    ));

    DutchAnimRuntime.instance.addListener(_onAnimRuntimeForHandMask);
    _lastAnimRuntimeStabilitySig = _computeAnimRuntimeStabilitySig();
  }

  String _computeAnimRuntimeStabilitySig() {
    final snap = DutchAnimRuntime.instance.snapshotForAnim();
    final q = snap[DutchAnimRuntime.eventDataKey] as List? ?? [];
    return '${DutchAnimRuntime.instance.handAnimMaskSignature}|${q.length}';
  }

  void _onAnimRuntimeForHandMask() {
    if (!mounted) return;
    final sig = _computeAnimRuntimeStabilitySig();
    if (sig == _lastAnimRuntimeStabilitySig) return;
    _lastAnimRuntimeStabilitySig = sig;
    setState(() {});
  }

  /// Hides the real hand card at [playerId]/[handIndex] while [DutchCardAnimOverlay] masks that slot.
  Widget _wrapHandSlotAnimMask(String playerId, int handIndex, Widget child) {
    if (DutchAnimRuntime.instance.isAnimMaskedHandSlot(playerId, handIndex)) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: child,
        ),
      );
    }
    return child;
  }

  void _scheduleAnimLayoutReport() {
    final d = StateManager().getModuleState<Map<String, dynamic>>('dutch_game');
    final currentGameId = d?['currentGameId']?.toString() ?? '';
    if (currentGameId.isEmpty) {
      _lastAnimLayoutSignature = null;
      return;
    }
    if (_animLayoutCommitScheduled) return;
    _animLayoutCommitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animLayoutCommitScheduled = false;
      if (!mounted) return;
      final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game');
      if (dutch == null) return;
      final board = _unifiedBoardViewSlice(dutch);
      _flushAnimLayoutReport(board);
    });
  }

  /// [CardTableOrientation.name] per player for [DutchCardAnimOverlay] (matches seat buckets).
  Map<String, String> _playerTableOrientationKeys(Map<String, dynamic> board) {
    final myId = _myBoardPlayerId(board);
    final out = <String, String>{myId: CardTableOrientation.portraitUp.name};
    final opponentsPanel = board['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final buckets = bucketOpponentsForDutchTable(opponents);
    void tag(List<Map<String, dynamic>> list, CardTableOrientation o) {
      for (final p in list) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty) out[id] = o.name;
      }
    }
    tag(buckets.top, CardTableOrientation.portraitDown);
    tag(buckets.left, CardTableOrientation.landscapeFromLeft);
    tag(buckets.right, CardTableOrientation.landscapeFromRight);
    return out;
  }

  void _flushAnimLayoutReport(Map<String, dynamic> board) {
    if (_animStackAnchorKey.currentContext == null) return;
    final uid = _myBoardPlayerId(board);
    final slotPathToKey = <String, GlobalKey>{};
    final myHand = board['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    for (int i = 0; i < cards.length; i++) {
      final mapKey = 'my_hand_${uid}_$i';
      final g = _cardKeys[mapKey];
      if (g != null) slotPathToKey['$uid|$i'] = g;
    }
    final players = (board['boardGameState'] as Map<String, dynamic>? ?? {})['players'] as List<dynamic>? ?? [];
    for (final p in players) {
      if (p is! Map<String, dynamic>) continue;
      final pid = p['id']?.toString() ?? '';
      if (pid.isEmpty || pid == uid) continue;
      final hand = p['hand'] as List<dynamic>? ?? [];
      for (int i = 0; i < hand.length; i++) {
        final mapKey = 'opponent_${pid}_$i';
        final g = _cardKeys[mapKey];
        if (g != null) slotPathToKey['$pid|$i'] = g;
      }
    }
    final hands = DutchAnimLayoutReporter.captureHandSlots(_animStackAnchorKey, slotPathToKey);
    final piles = DutchAnimLayoutReporter.capturePiles(
      _animStackAnchorKey,
      drawPileKey: _drawPileKey,
      discardPileKey: _discardPileKey,
    );
    final orientKeys = _playerTableOrientationKeys(board);
    final sig = '${jsonEncode(hands)}|${jsonEncode(piles)}|${jsonEncode(orientKeys)}';
    if (sig == _lastAnimLayoutSignature) {
      if (LOGGING_SWITCH) {
        _logger.debug(
          'DutchAnimLayout: flush skipped (signature unchanged) slotKeys=${slotPathToKey.length}',
        );
      }
      return;
    }
    _lastAnimLayoutSignature = sig;
    if (LOGGING_SWITCH) {
      final sample = slotPathToKey.keys.take(12).join(',');
      _logger.info(
        'DutchAnimLayout: flush mergeLayout slotKeys=${slotPathToKey.length} sample=[$sample]',
      );
    }
    DutchAnimRuntime.instance.mergeLayout(
      cardPositions: hands,
      pileRects: piles,
      playerTableOrientations: orientKeys,
    );
  }

  @override
  void dispose() {
    DutchAnimRuntime.instance.removeListener(_onAnimRuntimeForHandMask);
    _cardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer?.cancel();
    _selectedCardOverlayTimer?.cancel();
    _glowAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = LOGGING_SWITCH ? (Stopwatch()..start()) : null;

    final result = DutchSliceBuilder<Map<String, dynamic>>(
      selector: _unifiedBoardViewSlice,
      builder: (context, board, child) {
        _maybeResetLocalPlayFlagsForPhaseEntry(board);
        _scheduleAnimLayoutReport();
        return Stack(
          key: _animStackAnchorKey,
          clipBehavior: Clip.none,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (LOGGING_SWITCH) {
                  _logger.info('[GameBoard overflow] build: root constraints maxW=${constraints.maxWidth} maxH=${constraints.maxHeight} minW=${constraints.minWidth} minH=${constraints.minHeight}');
                }
                // Top strip (intrinsic height) → middle (fills) → my hand (intrinsic height)
                final ctx = _prepareOppBoardContext(board);
                if (LOGGING_SWITCH) {
                  final mh = board['myHand'] as Map<String, dynamic>? ?? {};
                  final myCards = mh['cards'] as List<dynamic>? ?? [];
                  final bgs = board['boardGameState'] as Map<String, dynamic>? ?? {};
                  String oppIds(List<Map<String, dynamic>> xs) =>
                      xs.map((e) => e['id']?.toString() ?? '?').join(',');
                  final rawPanel = board['opponentsPanel'] as Map<String, dynamic>? ?? {};
                  final rawList = rawPanel['opponents'] as List<dynamic>? ?? [];
                  _logger.info(
                    '[UnifiedGameBoard] slice gameId=${board['currentGameId']} gamePhase=${board['gamePhase']} '
                    'ssotPhase=${bgs['phase']} opps=${ctx.opponents.length} '
                    'bucketsTop/Left/Right=${ctx.buckets.top.length}/${ctx.buckets.left.length}/${ctx.buckets.right.length} '
                    'myHandCards=${myCards.length} isGameActive=${board['isGameActive']}',
                  );
                  _logger.info(
                    '[OppWidgets] opponentsPanel.rawCount=${rawList.length} '
                    'idsTop=[${oppIds(ctx.buckets.top)}] idsLeft=[${oppIds(ctx.buckets.left)}] idsRight=[${oppIds(ctx.buckets.right)}] '
                    'clockwiseOrder=[${ctx.opponents.map((e) => e is Map<String, dynamic> ? (e['id']?.toString() ?? '?') : '?').join(',')}]',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopOppStrip(board, ctx),
                    if (ctx.buckets.top.isNotEmpty) const SizedBox(height: 8),
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: _buildMiddlePlayRow(board, ctx),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildMyHand(board),
                  ],
                );
              },
            ),
            Positioned.fill(
              // Opponents / board ancestors may disable tickers; flight overlay has its own [Ticker].
              child: TickerMode(
                enabled: true,
                child: const DutchCardAnimOverlay(),
              ),
            ),
          ],
        );
      },
    );
    if (LOGGING_SWITCH && stopwatch != null) {
      stopwatch.stop();
      _unifiedWidgetRebuildCount++;
      _logger.info('📊 UnifiedGameBoardWidget REBUILD #$_unifiedWidgetRebuildCount duration=${stopwatch.elapsedMilliseconds} ms');
    }
    return result;
  }

  /// Resets play-surface local flags when entering `initial_peek`: first build already in peek, or any phase → `initial_peek`.
  void _maybeResetLocalPlayFlagsForPhaseEntry(Map<String, dynamic> board) {
    final gameState = board['boardGameState'] as Map<String, dynamic>? ?? {};
    final phase = gameState['phase'] as String?;

    if (phase != 'initial_peek') {
      _lastPhaseForLocalReset = phase;
      return;
    }

    final prev = _lastPhaseForLocalReset;
    final shouldReset = prev == null || prev != 'initial_peek';
    _lastPhaseForLocalReset = phase;

    if (shouldReset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(_resetLocalPlayFlagsForNewDeal);
      });
    }
  }

  void _resetLocalPlayFlagsForNewDeal() {
    _callFinalRoundTappedPending = false;
    _isProcessingAction = false;
    _clickedCardId = null;
    _clickedPileType = null;
    _initialPeekSelectionCount = 0;
    _initialPeekSelectedCardIds.clear();
    _isCardsToPeekProtected = false;
    _protectedCardsToPeek = null;
    _cardsToPeekProtectionTimer?.cancel();
    _cardsToPeekProtectionTimer = null;
    _isMyHandCardsToPeekProtected = false;
    _protectedMyHandCardsToPeek = null;
    _myHandCardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer = null;
    _selectedCardOverlayTimer?.cancel();
    _selectedCardOverlayTimer = null;
    _previousPlayerStatus = null;
    PlayerAction.resetJackSwapSelections();
  }
  
  // ========== Card Key Management ==========
  
  /// Get or create GlobalKey for a card (for widget identification)
  GlobalKey _getOrCreateCardKey(String cardId, String keyType) {
    final key = '${keyType}_$cardId';
    if (!_cardKeys.containsKey(key)) {
      _cardKeys[key] = GlobalKey(debugLabel: key);
    }
    return _cardKeys[key]!;
  }
  
  
  // ========== Opponents Panel Methods ==========

  /// Protect cardsToPeek data for 5 seconds
  void _protectCardsToPeek(List<dynamic> cardsToPeek) {
    _cardsToPeekProtectionTimer?.cancel();
    _isCardsToPeekProtected = true;
    _protectedCardsToPeek = List<dynamic>.from(cardsToPeek);
    _cardsToPeekProtectionTimer = Timer(Duration(seconds: 5), () {
      _clearCardsToPeekProtection();
    });
  }

  /// Clear cardsToPeek protection
  void _clearCardsToPeekProtection() {
    _isCardsToPeekProtected = false;
    _protectedCardsToPeek = null;
    _cardsToPeekProtectionTimer?.cancel();
    _cardsToPeekProtectionTimer = null;
    if (mounted) {
      setState(() {});
    }
  }

  _OppBoardContext _prepareOppBoardContext(Map<String, dynamic> board) {
    final opponentsPanel = board['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final currentTurnIndex = (opponentsPanel['currentTurnIndex'] as num?)?.toInt() ?? -1;
    final cardsToPeekFromState = board['myCardsToPeek'] as List<dynamic>? ?? [];

    if (cardsToPeekFromState.isNotEmpty && !_isCardsToPeekProtected) {
      final hasFullCardData = cardsToPeekFromState.any((card) {
        if (card is Map<String, dynamic>) {
          return card.containsKey('suit') || card.containsKey('rank');
        }
        return false;
      });
      if (hasFullCardData) {
        _protectCardsToPeek(cardsToPeekFromState);
      }
    }

    final cardsToPeek = _isCardsToPeekProtected && _protectedCardsToPeek != null
        ? _protectedCardsToPeek!
        : cardsToPeekFromState;

    final isGameActive = board['isGameActive'] ?? false;
    final playerStatus = board['playerStatus']?.toString() ?? 'unknown';

    return _OppBoardContext._(
      cardsToPeek: cardsToPeek,
      opponents: opponents,
      currentTurnIndex: currentTurnIndex,
      isGameActive: isGameActive,
      playerStatus: playerStatus,
    );
  }

  /// Full width, height from content, aligned to top of the play area.
  Widget _buildTopOppStrip(Map<String, dynamic> board, _OppBoardContext ctx) {
    if (ctx.buckets.top.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('[OppWidgets] _buildTopOppStrip → SizedBox.shrink (buckets.top empty; oppCount=${ctx.opponents.length})');
      }
      return const SizedBox.shrink();
    }
    if (LOGGING_SWITCH) {
      final ids = ctx.buckets.top.map((e) => e['id']?.toString() ?? '?').join(',');
      _logger.info(
        '[OppWidgets] _buildTopOppStrip building Row n=${ctx.buckets.top.length} topPlayerIds=[$ids] '
        '(Center + Row mainAxisSize.min; intrinsic width per seat)',
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppPadding.mediumPadding.left),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final topCount = ctx.buckets.top.length;
            final seatGap = 8.0;
            final totalGap = topCount > 1 ? (topCount - 1) * seatGap : 0.0;
            final rowWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final seatWidth = (rowWidth - totalGap) / (topCount <= 0 ? 1 : topCount);
            if (LOGGING_SWITCH) {
              _logger.info(
                '[OppWidgets] top-row constraints rowW=${rowWidth.toStringAsFixed(1)} '
                'topCount=$topCount seatW=${seatWidth.toStringAsFixed(1)}',
              );
            }
            return Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < topCount; i++) ...[
                  if (i > 0) SizedBox(width: seatGap),
                  SizedBox(
                    width: seatWidth,
                    child: _paddedOpponentSlot(
                      board,
                      ctx.buckets.top[i],
                      ctx.cardsToPeek,
                      ctx.currentTurnIndex,
                      ctx.isGameActive,
                      ctx.playerStatus,
                      ctx.opponents,
                      CardTableOrientation.portraitDown,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Left / center (bounded width) / right; fills all width and remaining height.
  ///
  /// Do **not** wrap [_buildGameBoard] in [IntrinsicWidth]: its inner [LayoutBuilder] plus
  /// intrinsic passes caused `shifted_box.dart` `child!.hasSize` / unbounded layout failures.
  Widget _buildMiddlePlayRow(Map<String, dynamic> board, _OppBoardContext ctx) {
    if (LOGGING_SWITCH) {
      _logger.info(
        '[UnifiedGameBoard] _buildMiddlePlayRow: opponentsEmpty=${ctx.opponents.isEmpty} '
        'left=${ctx.buckets.left.length} right=${ctx.buckets.right.length}',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final centerMaxW = (rowW * 0.34).clamp(150.0, 280.0);
        final centerBoard = Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: centerMaxW),
            child: _buildGameBoard(board),
          ),
        );

        if (ctx.opponents.isEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: SizedBox.shrink()),
              centerBoard,
              const Expanded(child: SizedBox.shrink()),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ctx.buckets.left.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: ctx.buckets.left
                          .map(
                            (p) => Expanded(
                              child: _paddedOpponentSlot(
                                board,
                                p,
                                ctx.cardsToPeek,
                                ctx.currentTurnIndex,
                                ctx.isGameActive,
                                ctx.playerStatus,
                                ctx.opponents,
                                CardTableOrientation.landscapeFromLeft,
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            centerBoard,
            Expanded(
              child: ctx.buckets.right.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: ctx.buckets.right
                          .map(
                            (p) => Expanded(
                              child: _paddedOpponentSlot(
                                board,
                                p,
                                ctx.cardsToPeek,
                                ctx.currentTurnIndex,
                                ctx.isGameActive,
                                ctx.playerStatus,
                                ctx.opponents,
                                CardTableOrientation.landscapeFromRight,
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _paddedOpponentSlot(
    Map<String, dynamic> board,
    Map<String, dynamic> player,
    List<dynamic> cardsToPeek,
    int currentTurnIndex,
    bool isGameActive,
    String playerStatus,
    List<dynamic> opponentsFull,
    CardTableOrientation cardTableOrientation,
  ) {
    final currentPlayerMap = board['currentPlayer'] as Map<String, dynamic>? ?? {};
    final currentPlayerId = currentPlayerMap['id']?.toString() ?? '';
    final originalIndexMap = <String, int>{};
    for (int i = 0; i < opponentsFull.length; i++) {
      final pl = opponentsFull[i] as Map<String, dynamic>;
      final pid = pl['id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        originalIndexMap[pid] = i;
      }
    }
    final playerId = player['id']?.toString() ?? '';
    final originalIndex = originalIndexMap[playerId] ?? 0;
    final isCurrentTurn = originalIndex == currentTurnIndex;
    final isCurrentPlayer = playerId == currentPlayerId;
    final knownCards = player['known_cards'] as Map<String, dynamic>?;
    final bgs = board['boardGameState'] as Map<String, dynamic>? ?? {};
    final phase = bgs['phase'] as String?;
    final timerConfigRaw = bgs['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map(
          (key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30),
        ) ??
        <String, int>{};
    final gamePhase = board['gamePhase']?.toString() ?? 'waiting';
    final isInitialPeekPhase = gamePhase == 'initial_peek';
    final currentPlayerStatus = _getCurrentUserStatus();

    if (LOGGING_SWITCH) {
      _logger.info(
        '[OppWidgets] _paddedOpponentSlot build playerId=$playerId orientation=$cardTableOrientation '
        'isCurrentTurn=$isCurrentTurn handLen=${(player['hand'] as List?)?.length ?? 0}',
      );
    }

    final sideColumnOpp = cardTableOrientation == CardTableOrientation.landscapeFromLeft ||
        cardTableOrientation == CardTableOrientation.landscapeFromRight;

    final panel = _buildOpponentCard(
      player,
      cardsToPeek,
      player['collection_rank_cards'] as List<dynamic>? ?? [],
      isCurrentTurn,
      isGameActive,
      isCurrentPlayer,
      currentPlayerStatus,
      knownCards,
      isInitialPeekPhase,
      phase,
      timerConfig,
      cardTableOrientation: cardTableOrientation,
      centerVerticallyInSideColumn: sideColumnOpp,
    );

    final horizontalPad = sideColumnOpp
        ? AppPadding.mediumPadding.left
        : AppPadding.smallPadding.left;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: sideColumnOpp
          ? Align(
              alignment: cardTableOrientation == CardTableOrientation.landscapeFromRight
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: panel,
            )
          : panel,
    );
  }

  Widget _buildOpponentCard(Map<String, dynamic> player, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, bool isCurrentTurn, bool isGameActive, bool isCurrentPlayer, String currentPlayerStatus, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, String? phase, Map<String, int>? timerConfig, {required CardTableOrientation cardTableOrientation, bool centerVerticallyInSideColumn = false}) {
    final hand = player['hand'] as List<dynamic>? ?? [];
    final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
    final hasCalledDutch = player['hasCalledDutch'] ?? false;
    final playerStatus = player['status']?.toString() ?? 'unknown';
    
    // For timer calculation, always use playerStatus (opponent's actual status)
    // currentPlayerStatus is the user's status (used for card glow), not the opponent's status
    // For timer, we need the opponent's actual status to get the correct duration
    final statusForTimer = playerStatus;
    
    // Calculate timer from game_state timerConfig (status is more specific than phase)
    int? effectiveTimer;
    
    // Check status first (more specific than phase for player actions)
    if (statusForTimer.isNotEmpty) {
      switch (statusForTimer) {
        case 'initial_peek':
          effectiveTimer = timerConfig?['initial_peek'] ?? 15;
          break;
        case 'drawing_card':
          effectiveTimer = timerConfig?['drawing_card'] ?? 20;
          break;
        case 'playing_card':
          effectiveTimer = timerConfig?['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          effectiveTimer = timerConfig?['same_rank_window'] ?? 10;
          break;
        case 'queen_peek':
          effectiveTimer = timerConfig?['queen_peek'] ?? 15;
          break;
        case 'jack_swap':
          effectiveTimer = timerConfig?['jack_swap'] ?? 20;
          break;
        case 'peeking':
          effectiveTimer = timerConfig?['peeking'] ?? 10;
          break;
        case 'waiting':
          effectiveTimer = timerConfig?['waiting'] ?? 0;
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (effectiveTimer == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          effectiveTimer = timerConfig?['initial_peek'] ?? 15;
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          effectiveTimer = timerConfig?['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          effectiveTimer = timerConfig?['same_rank_window'] ?? 10;
          break;
        case 'queen_peek_window':
          effectiveTimer = timerConfig?['queen_peek'] ?? 15;
          break;
        case 'special_play_window':
          effectiveTimer = timerConfig?['jack_swap'] ?? 20;
          break;
        default:
          effectiveTimer = timerConfig?['default'] ?? 30;
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    effectiveTimer ??= 30;
    
    // Ensure effectiveTimer is valid (not 0, not negative, not NaN) to prevent division by zero in timer widget
    if (effectiveTimer <= 0 || !effectiveTimer.isFinite) {
      effectiveTimer = 30; // Safe default
    }
    
    // Show timer when: player has any active status (drawing_card, playing_card, initial_peek, jack_swap, queen_peek, peeking)
    // Note: 'peeking' status occurs after a queen_peek decision is executed, but timer should continue showing
    // Use playerStatus (opponent's actual status) to determine if timer should show
    final shouldShowTimer = playerStatus == 'drawing_card' || 
         playerStatus == 'playing_card' || 
         playerStatus == 'initial_peek' ||
         playerStatus == 'jack_swap' || 
         playerStatus == 'queen_peek' || 
         playerStatus == 'peeking';
    
    // For timer color, always get the status chip color (including same_rank_window)
    final timerColor = _getStatusChipColor(playerStatus);

    late final Alignment cardAlignment;
    late final MainAxisAlignment nameAlignment;
    late final CrossAxisAlignment columnAlignment;
    final MainAxisAlignment columnMainAlignment = MainAxisAlignment.start;
    switch (cardTableOrientation) {
      case CardTableOrientation.portraitDown:
        cardAlignment = Alignment.center;
        nameAlignment = MainAxisAlignment.center;
        columnAlignment = CrossAxisAlignment.center;
        break;
      case CardTableOrientation.landscapeFromRight:
        cardAlignment = Alignment.centerRight;
        nameAlignment = MainAxisAlignment.end;
        columnAlignment = CrossAxisAlignment.end;
        break;
      case CardTableOrientation.landscapeFromLeft:
        cardAlignment = Alignment.centerLeft;
        nameAlignment = MainAxisAlignment.start;
        columnAlignment = CrossAxisAlignment.start;
        break;
      case CardTableOrientation.portraitUp:
        cardAlignment = Alignment.centerLeft;
        nameAlignment = MainAxisAlignment.start;
        columnAlignment = CrossAxisAlignment.start;
        break;
    }

    // In opponent slots, "current turn" already means this seat is the active actor.
    // Do not gate on isCurrentPlayer here, otherwise highlights never appear.
    final isOpponentTurn = isCurrentTurn;
    final highlightOpponentSeat = isOpponentTurn && isGameActive;
    if (LOGGING_SWITCH) {
      _logger.info(
        '[TurnHighlight] oppId=${player['id']} '
        'isCurrentTurn=$isCurrentTurn isCurrentPlayer=$isCurrentPlayer '
        'isGameActive=$isGameActive highlight=$highlightOpponentSeat '
        'status=$playerStatus phase=$phase',
      );
    }

    final Widget? opponentHandHudBar = hand.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: highlightOpponentSeat ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: shouldShowTimer
                    ? CircularTimerWidget(
                        key: ValueKey('timer_${player['id']}_${playerStatus}'),
                        durationSeconds: effectiveTimer,
                        size: highlightOpponentSeat ? (_kHudRingOuter + 4) : _kHudRingOuter,
                        strokeWidth: highlightOpponentSeat ? (_kHudRingStroke + 0.5) : _kHudRingStroke,
                        color: timerColor,
                        backgroundColor: AppColors.surfaceVariant,
                        centerChild: _buildPlayerProfilePicture(
                          player['id']?.toString() ?? '',
                          profilePictureUrl: player['profile_picture']?.toString(),
                          diameter: _kHudAvatarInRing,
                        ),
                      )
                    : _buildPlayerProfilePicture(
                        player['id']?.toString() ?? '',
                        profilePictureUrl: player['profile_picture']?.toString(),
                      ),
              ),
              if (hasCalledDutch || isOpponentTurn) ...[
                const SizedBox(width: 8),
                if (hasCalledDutch) ...[
                  Icon(Icons.flag, size: 16, color: AppColors.errorColor),
                  if (isOpponentTurn) const SizedBox(width: 4),
                ],
                if (isOpponentTurn)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentColor2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'TURN',
                      style: AppTextStyles.overline().copyWith(
                        color: AppColors.textOnAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final handPanel = hand.isNotEmpty
            ? _buildOpponentsCardsRow(
                hand,
                cardsToPeek,
                playerCollectionRankCards,
                drawnCard,
                player['id']?.toString() ?? '',
                knownCards,
                isInitialPeekPhase,
                player,
                nameAlignment: nameAlignment,
                currentPlayerStatus: currentPlayerStatus,
                cardTableOrientation: cardTableOrientation,
                handHudBar: opponentHandHudBar,
                handHudCorner: _handHudCornerForTableOrientation(cardTableOrientation),
              )
            : _buildEmptyHand();

        final decoratedHandPanel = AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(highlightOpponentSeat ? 4 : 0),
          decoration: BoxDecoration(
            color: highlightOpponentSeat ? timerColor.withOpacity(0.12) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlightOpponentSeat ? timerColor : Colors.transparent,
              width: highlightOpponentSeat ? 2.0 : 0.0,
            ),
            boxShadow: highlightOpponentSeat
                ? [
                    BoxShadow(
                      color: timerColor.withOpacity(0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: handPanel,
        );
        if (LOGGING_SWITCH) {
          _logger.info(
            '[TurnHighlight] render oppId=${player['id']} '
            'orientation=$cardTableOrientation highlighted=$highlightOpponentSeat '
            'hand=${hand.length}',
          );
        }

        return Column(
          crossAxisAlignment: columnAlignment,
          mainAxisAlignment: columnMainAlignment,
          mainAxisSize: centerVerticallyInSideColumn ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Align(
              alignment: cardAlignment,
              child: decoratedHandPanel,
            ),
          ],
        );
      },
    );
  }

  /// Matches [CardWidget] / [CardTableOrientation] for non-[CardWidget] slots (blank).
  Widget _orientOpponentHandChild(Widget portraitSizedChild, Size portraitDimensions, CardTableOrientation orientation) {
    final core = SizedBox(width: portraitDimensions.width, height: portraitDimensions.height, child: portraitSizedChild);
    switch (orientation) {
      case CardTableOrientation.portraitUp:
        return core;
      case CardTableOrientation.portraitDown:
        return RotatedBox(quarterTurns: 2, child: core);
      case CardTableOrientation.landscapeFromLeft:
        return RotatedBox(quarterTurns: 1, child: core);
      case CardTableOrientation.landscapeFromRight:
        return RotatedBox(quarterTurns: 3, child: core);
    }
  }

  Widget _buildOpponentsCardsRow(
    List<dynamic> cards,
    List<dynamic> cardsToPeek,
    List<dynamic> playerCollectionRankCards,
    Map<String, dynamic>? drawnCard,
    String playerId,
    Map<String, dynamic>? knownCards,
    bool isInitialPeekPhase,
    Map<String, dynamic> player, {
    MainAxisAlignment? nameAlignment,
    String? currentPlayerStatus,
    required CardTableOrientation cardTableOrientation,
    Widget? handHudBar,
    _HandHudCorner? handHudCorner,
  }) {
    final ownerCardBackId = player['card_back_id']?.toString();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use available width (after column padding) for all calculations
        // constraints.maxWidth is already the available space after padding
        final availableWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
        // Ensure availableWidth is valid before calculations
        if (availableWidth <= 0 || !availableWidth.isFinite) {
          return const SizedBox.shrink();
        }
        // Left/right columns: vertical stack — shrink cards so all fit in column height + width.
        // Top/bottom: single row — shrink cards so all fit (no Wrap overflow).
        final sideColumnVerticalHand = cardTableOrientation == CardTableOrientation.landscapeFromLeft ||
            cardTableOrientation == CardTableOrientation.landscapeFromRight;

        late final double slotGap;
        late final Size cardDimensions;
        late final double stackOffset;

        final slotCount = cards.isEmpty ? 1 : cards.length;
        final boundedHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : null;

        if (sideColumnVerticalHand) {
          slotGap = 6.0;
          cardDimensions = _adaptiveCardSize(
            availableWidth: availableWidth,
            slots: slotCount,
            slotGap: slotGap,
            availableHeight: boundedHeight,
            verticalStack: true,
            minWidth: 1.0,
          );
          stackOffset = cardDimensions.height * CardDimensions.STACK_OFFSET_PERCENTAGE;
        } else {
          slotGap = availableWidth * 0.02;
          cardDimensions = _adaptiveCardSize(
            availableWidth: availableWidth,
            slots: slotCount,
            slotGap: slotGap,
            availableHeight: boundedHeight,
            minWidth: 1.0,
          );
          stackOffset = cardDimensions.height * CardDimensions.STACK_OFFSET_PERCENTAGE;
        }

        final EdgeInsets handSlotPadding =
            sideColumnVerticalHand ? EdgeInsets.zero : EdgeInsets.only(right: slotGap);

        Widget applyOppHandHudIfFirst(int index, Widget slotContent) {
          final bar = handHudBar;
          final corner = handHudCorner;
          if (index != 0 || bar == null || corner == null) return slotContent;
          return _stackHandHudOnFirstCardSlot(
            cardSlot: slotContent,
            corner: corner,
            hud: bar,
          );
        }
        
        final collectionRankCardIds = playerCollectionRankCards
            .where((c) => c is Map<String, dynamic>)
            .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
            .where((id) => id != null)
            .toSet();
        
        Map<String, Widget> collectionRankWidgets = {};
        
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          if (card == null) continue;
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          Map<String, dynamic>? peekedCardData;
          if (cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          Map<String, dynamic>? collectionRankCardData;
          if (playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                break;
              }
            }
          }
          if (collectionRankCardData != null) {
            final cardDataToUse = isDrawnCard && drawnCard != null
                ? drawnCard 
                : (peekedCardData ?? collectionRankCardData);
            final cardKey = _getOrCreateCardKey('${playerId}_$i', 'opponent');
            final cardWidget = _buildOpponentCardWidget(
              cardDataToUse,
              isDrawnCard,
              playerId,
              false,
              cardDimensions,
              cardKey: cardKey,
              cardTableOrientation: cardTableOrientation,
              ownerCardBackId: ownerCardBackId,
            );
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        // Build list of card widgets
        List<Widget> cardWidgets = [];
        
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          if (card == null) {
            final blankSlotKey = _getOrCreateCardKey('${playerId}_$index', 'opponent');
            cardWidgets.add(
              Padding(
                padding: handSlotPadding,
                child: applyOppHandHudIfFirst(
                  index,
                  Container(
                    key: blankSlotKey,
                    child: _orientOpponentHandChild(
                      _buildBlankCardSlot(cardDimensions),
                      cardDimensions,
                      cardTableOrientation,
                    ),
                  ),
                ),
              ),
            );
            continue;
          }
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          Map<String, dynamic>? collectionRankCardData;
          bool isCollectionRankCard = false;
          if (cardId != null && playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                isCollectionRankCard = true;
                break;
              }
            }
          }
          final cardDataToUse = isDrawnCard && drawnCard != null 
              ? drawnCard 
              : (peekedCardData ?? collectionRankCardData ?? cardMap);
          
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            bool isFirstCollectionCard = true;
            for (int i = 0; i < index; i++) {
              final prevCard = cards[i];
              if (prevCard != null && prevCard is Map<String, dynamic>) {
                final prevCardId = prevCard['cardId']?.toString();
                if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                  isFirstCollectionCard = false;
                  break;
                }
              }
            }
            if (isFirstCollectionCard) {
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in playerCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    orderedCollectionWidgets.add(collectionRankWidgets[collectionCardId]!);
                  }
                }
              }
              final cardWidth = cardDimensions.width;
              final cardHeight = cardDimensions.height;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              final stackKey = _getOrCreateCardKey('${playerId}_$index', 'opponent');
              final stackWidget = Container(
                key: stackKey,
                width: cardWidth,
                height: stackHeight,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: orderedCollectionWidgets.asMap().entries.map((entry) {
                    return Positioned(
                      left: 0,
                      top: entry.key * stackOffset,
                      child: entry.value,
                    );
                  }).toList(),
                ),
              );
              cardWidgets.add(
                Padding(
                  padding: handSlotPadding,
                  child: applyOppHandHudIfFirst(
                    index,
                    _wrapHandSlotAnimMask(playerId, index, stackWidget),
                  ),
                ),
              );
            }
            // Skip non-first collection cards (they're already in the stack)
            continue;
          }
          if (cardId == null) {
            continue;
          }
          final cardKey = _getOrCreateCardKey('${playerId}_$index', 'opponent');
          final cardWidget = _buildOpponentCardWidget(
            cardDataToUse,
            isDrawnCard,
            playerId,
            false,
            cardDimensions,
            cardKey: cardKey,
            currentPlayerStatus: currentPlayerStatus,
            cardTableOrientation: cardTableOrientation,
            ownerCardBackId: ownerCardBackId,
          );
          cardWidgets.add(
            Padding(
              padding: handSlotPadding,
              child: applyOppHandHudIfFirst(
                index,
                _wrapHandSlotAnimMask(playerId, index, cardWidget),
              ),
            ),
          );
        }

        // Right column: hand index 0 is nearest the center board; show top→bottom as high index first.
        if (sideColumnVerticalHand &&
            cardTableOrientation == CardTableOrientation.landscapeFromRight) {
          cardWidgets = cardWidgets.reversed.toList();
        }

        // Top strip (portraitDown): same as right column — visual order so index 0 sits toward the center board.
        if (!sideColumnVerticalHand &&
            cardTableOrientation == CardTableOrientation.portraitDown) {
          cardWidgets = cardWidgets.reversed.toList();
        }

        if (sideColumnVerticalHand) {
          final handCross = cardTableOrientation == CardTableOrientation.landscapeFromRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: handCross,
            children: [
              for (int i = 0; i < cardWidgets.length; i++) ...[
                if (i > 0) SizedBox(height: slotGap),
                cardWidgets[i],
              ],
            ],
          );
        }

        return Row(
          mainAxisAlignment: cardTableOrientation == CardTableOrientation.portraitDown
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: cardWidgets,
        );
      },
    );
  }

  Widget _buildOpponentCardWidget(
    Map<String, dynamic> card,
    bool isDrawnCard,
    String playerId,
    bool isCollectionRankCard,
    Size cardDimensions, {
    GlobalKey? cardKey,
    String? currentPlayerStatus,
    required CardTableOrientation cardTableOrientation,
    String? ownerCardBackId,
  }) {
    final cardModel = CardModel.fromMap(card);
    final cardId = card['cardId']?.toString();
    final isSelected = cardId != null && _clickedCardId == cardId;
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forOpponent().copyWith(tableOrientation: cardTableOrientation),
      ownerCardBackId: ownerCardBackId,
      isSelected: isSelected,
      onTap: () => _handleOpponentCardClick(card, playerId),
    );
    
    // Apply glow effect based on current player status (for jack_swap and queen_peek)
    final glowColor = currentPlayerStatus != null 
        ? _getGlowColorForCards(currentPlayerStatus, false) 
        : null;
    
    if (glowColor != null && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) {
          final glowOpacity = _glowAnimation!.value;
          final glowDecoration = _buildGlowDecoration(glowColor, glowOpacity);
          return Container(
            decoration: glowDecoration,
            child: cardWidget,
          );
        },
      );
    }
    
    return cardWidget;
  }

  Widget _buildEmptyHand() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'No cards',
              style: AppTextStyles.overline().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlankCardSlot([Size? cardDimensions]) {
    final dimensions = cardDimensions ?? CardDimensions.getUnifiedDimensions();
    // Use dynamic border radius from SSOT to match card widgets
    final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // Background — same color as border
            Positioned.fill(
              child: Container(
                color: AppColors.accentColor,
              ),
            ),
            // Border overlay — use theme accent (green in Dutch/green preset) per THEME_SYSTEM.md
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: AppColors.accentColor,
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? getClickedCardId() {
    return _clickedCardId;
  }

  void clearClickedCardId() {
    setState(() {
      _clickedCardId = null;
    });
  }

  /// Schedules removal of all selected-card overlays (opponent highlight + my hand selection) after 3 seconds.
  /// Cancels any existing schedule when called again.
  void _startSelectedOverlayClearTimer() {
    _selectedCardOverlayTimer?.cancel();
    _selectedCardOverlayTimer = Timer(const Duration(seconds: 3), () {
      _selectedCardOverlayTimer = null;
      if (!mounted) return;
      setState(() {
        _clickedCardId = null;
      });
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      final myHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
      if (currentGameId.isNotEmpty && games.containsKey(currentGameId)) {
        final currentGame = Map<String, dynamic>.from(games[currentGameId]);
        currentGame['selectedCardIndex'] = -1;
        final updatedGames = Map<String, dynamic>.from(games);
        updatedGames[currentGameId] = currentGame;
        final updatedMyHand = Map<String, dynamic>.from(myHand);
        updatedMyHand['selectedIndex'] = -1;
        updatedMyHand['selectedCard'] = null;
        StateManager().updateModuleState('dutch_game', {
          'games': updatedGames,
          'myHand': updatedMyHand,
        });
      } else {
        final updatedMyHand = Map<String, dynamic>.from(myHand);
        updatedMyHand['selectedIndex'] = -1;
        updatedMyHand['selectedCard'] = null;
        StateManager().updateModuleState('dutch_game', {
          'myHand': updatedMyHand,
        });
      }
    });
  }

  void _handleOpponentCardClick(Map<String, dynamic> card, String cardOwnerId) async {
    final dutchGameState = _dutchGameState();
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final currentPlayerStatus = _getCurrentUserStatus();
    
    if (currentPlayerStatus == 'jack_swap') {
      if (LOGGING_SWITCH) {
        _logger.info('🃏 OpponentsPanelWidget: Status is jack_swap - opponent cards are interactive');
      }
    }
    if (currentPlayerStatus == 'queen_peek' || currentPlayerStatus == 'jack_swap') {
      final cardId = card['cardId']?.toString();
      if (cardId != null) {
        setState(() {
          _clickedCardId = cardId;
        });
        _startSelectedOverlayClearTimer();

        if (currentPlayerStatus == 'queen_peek') {
          try {
            final queenPeekAction = PlayerAction.queenPeek(
              gameId: currentGameId,
              cardId: cardId,
              ownerId: cardOwnerId,
            );
            await queenPeekAction.execute();
          } catch (e) {
            // Game feedback: snackbars removed
          }
        } else if (currentPlayerStatus == 'jack_swap') {
          try {
            if (LOGGING_SWITCH) {
              _logger.info('🃏 OpponentsPanelWidget: Card tapped during jack_swap - Card: $cardId, Player: $cardOwnerId, Game: $currentGameId');
            }
            if (LOGGING_SWITCH) {
              _logger.info('🃏 OpponentsPanelWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}');
            }
            await PlayerAction.selectCardForJackSwap(
              cardId: cardId,
              playerId: cardOwnerId,
              gameId: currentGameId,
            );
            final selectionCount = PlayerAction.getJackSwapSelectionCount();
            if (LOGGING_SWITCH) {
              _logger.info('🃏 OpponentsPanelWidget: After selection, jack swap count: $selectionCount');
            }
            if (selectionCount == 1) {
              // Game feedback: snackbars removed
            } else if (selectionCount == 2) {
              // Game feedback: snackbars removed
            }
          } catch (e) {
            // Game feedback: snackbars removed
          }
        }
      } else {
        // Game feedback: snackbars removed
      }
    } else {
      // Game feedback: snackbars removed
    }
  }

  Color _getStatusChipColor(String status) {
    switch (status) {
      case 'waiting':
        return AppColors.statusWaiting;
      case 'ready':
        return AppColors.statusReady;
      case 'drawing_card':
        return AppColors.statusDrawing;
      case 'playing_card':
        return AppColors.statusPlaying;
      case 'same_rank_window':
        return AppColors.statusSameRank;
      case 'queen_peek':
        return AppColors.statusQueenPeek;
      case 'jack_swap':
        return AppColors.statusJackSwap;
      case 'peeking':
        return AppColors.statusPeeking;
      case 'initial_peek':
        return AppColors.statusInitialPeek;
      case 'winner':
        return AppColors.statusWinner;
      case 'finished':
        return AppColors.statusFinished;
      case 'disconnected':
        return AppColors.errorColor;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Reusable glow effect decoration builder.
  /// Full opacity, tight spread (less blur/spread for a more visible edge glow).
  /// [statusColor] The color to use for the glow (from _getStatusChipColor)
  /// [glowOpacity] The current animation opacity value (from _glowAnimation)
  BoxDecoration? _buildGlowDecoration(Color statusColor, double glowOpacity) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
          color: statusColor.withValues(alpha: 1.0 * glowOpacity),
          blurRadius: 4,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: statusColor.withValues(alpha: 0.85 * glowOpacity),
          blurRadius: 8,
          spreadRadius: 0.5,
        ),
        BoxShadow(
          color: statusColor.withValues(alpha: 0.6 * glowOpacity),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ],
    );
  }

  /// Determine if glow should be applied to cards based on current status
  /// [currentPlayerStatus] The current player's status
  /// [isMyHand] Whether this is for my hand (true) or opponent hand (false)
  /// Returns the status color if glow should be applied, null otherwise
  Color? _getGlowColorForCards(String currentPlayerStatus, bool isMyHand) {
    switch (currentPlayerStatus) {
      case 'playing_card':
        // During playing: apply to all cards in my hand
        return isMyHand ? _getStatusChipColor(currentPlayerStatus) : null;
      case 'jack_swap':
      case 'queen_peek':
        // During jack swap/queen peek: apply to all cards in all hands
        return _getStatusChipColor(currentPlayerStatus);
      case 'initial_peek':
      case 'same_rank_window':
        // During initial peek/same rank: apply to my hand only
        return isMyHand ? _getStatusChipColor(currentPlayerStatus) : null;
      default:
        return null;
    }
  }

  // ========== Game Board Methods ==========

  /// Horizontal padding used by draw/discard pile (Padding.all(2) => 2 left + 2 right).
  static const double _gameBoardPileHorizontalPadding = 4;

  /// Card dimensions for game board piles: use full column width minus padding, clamped to max.
  static Size _gameBoardPileCardDimensions(double columnWidth) {
    final cardWidth = CardDimensions.clampCardWidth(columnWidth - _gameBoardPileHorizontalPadding);
    final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
    return Size(cardWidth, cardHeight);
  }

  Widget _buildGameBoard(Map<String, dynamic> board) {
    // Update game board height in state after build, but schedule only once per frame.
    if (!_gameBoardHeightUpdateScheduled) {
      _gameBoardHeightUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gameBoardHeightUpdateScheduled = false;
        _updateGameBoardHeight();
      });
    }
    
    return Container(
      key: _gameBoardKey,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Draw + discard centered in stretch space; match pot anchored to bottom of middle column.
          final gameboardRowWidth = constraints.maxWidth;
          final gameboardMaxHeight = constraints.maxHeight;
          if (LOGGING_SWITCH) {
            _logger.info('[GameBoard overflow] _buildGameBoard: constraints maxW=$gameboardRowWidth maxH=$gameboardMaxHeight');
          }
          return Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, c) =>
                            _buildDrawPile(availableWidth: c.maxWidth, board: board),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, c) =>
                            _buildDiscardPile(availableWidth: c.maxWidth, board: board),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildMatchPotRow(gameboardRowWidth, board),
            ],
          );
        },
      ),
    );
  }
  
  /// Update game board height in StateManager (for overlay positioning)
  void _updateGameBoardHeight() {
    if (_gameBoardKey.currentContext != null) {
      final RenderBox renderBox = _gameBoardKey.currentContext!.findRenderObject() as RenderBox;
      final height = renderBox.size.height;
      if (_lastPublishedGameBoardHeight != null &&
          (height - _lastPublishedGameBoardHeight!).abs() < 0.5) {
        return;
      }
      final stateManager = StateManager();
      final currentGameBoardHeight = stateManager.getModuleState<Map<String, dynamic>>('dutch_game')?['gameBoardHeight'] as double?;
      
      if (currentGameBoardHeight == null || (currentGameBoardHeight - height).abs() >= 0.5) {
        _lastPublishedGameBoardHeight = height;
        stateManager.updateModuleState('dutch_game', {
          'gameBoardHeight': height,
        });
      }
    }
  }

  // ========== Draw Pile Methods ==========

  /// Draw pile card size: scales with [availableWidth] (like opponent hand cards), clamped to [CardDimensions.MAX_CARD_WIDTH].
  Widget _buildDrawPile({double? availableWidth, required Map<String, dynamic> board}) {
    if (LOGGING_SWITCH) {
      _logger.info('[GameBoard overflow] _buildDrawPile: availableWidth=$availableWidth');
    }
    final drawPile = board['drawPile'] as List<dynamic>? ?? [];
    
    // Check if player is in drawing status (similar to myHand logic)
    final myHand = board['myHand'] as Map<String, dynamic>? ?? {};
    final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
    final isDrawingStatus = playerStatus == 'drawing_card';
    final statusChipColor = isDrawingStatus ? _getStatusChipColor(playerStatus) : null;
    
    return Container(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final Size cardDimensions = availableWidth != null && availableWidth > 0
                    ? _gameBoardPileCardDimensions(availableWidth)
                    : CardDimensions.getUnifiedDimensions();
                if (LOGGING_SWITCH) {
                  _logger.info('[GameBoard overflow] _buildDrawPile: cardDimensions=${cardDimensions.width}x${cardDimensions.height} (with padding 2 total 4)');
                }
                Widget drawPileContent;
              
              if (drawPile.isEmpty) {
                // Empty draw pile - render placeholder. Key on card-sized SizedBox so animation bounds match card size.
                final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
                drawPileContent = SizedBox(
                  key: _drawPileKey,
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: CardWidget(
                    key: emptyKey,
                    card: CardModel(
                      cardId: 'draw_pile_empty',
                      rank: '?',
                      suit: '?',
                      points: 0,
                    ),
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forDrawPile(),
                    showBack: true,
                    onTap: _handleDrawPileClick,
                  ),
                );
              } else {
                // Render all cards in draw pile with stacking effect
                // Only the top card is visible and clickable, but all are tracked for animation
                final topCardIndex = drawPile.length - 1;
                final topCardData = drawPile[topCardIndex] as Map<String, dynamic>? ?? {};
                
                // Create stacking effect with 2 additional cards behind
                final stackCards = <Widget>[];
                
                // Add 2 background cards with rotation and offset for stacking effect
                for (int i = 0; i < 2; i++) {
                  // Draw pile: 2° and 4° anticlockwise
                  final rotation = -(i + 1) * 2.0; // -2° and -4° (anticlockwise)
                  final offset = (i + 1) * 1.5; // 1.5px and 3px offset
                  // Add shadow to the last (bottom) card of the stack
                  final isBottomCard = i == 1; // Second card is the bottom one
                  stackCards.add(
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: rotation * 3.14159 / 180, // Convert to radians
                        child: Transform.translate(
                          offset: Offset(offset, -offset),
                          child: isBottomCard
                              ? Container(
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Opacity(
                                    opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                    child: CardWidget(
                                      card: CardModel.fromMap(topCardData),
                                      dimensions: cardDimensions,
                                      config: CardDisplayConfig.forDrawPile(),
                                      showBack: true,
                                      onTap: null, // Background cards not clickable
                                    ),
                                  ),
                                )
                              : Opacity(
                                  opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                  child: CardWidget(
                                    card: CardModel.fromMap(topCardData),
                                    dimensions: cardDimensions,
                                    config: CardDisplayConfig.forDrawPile(),
                                    showBack: true,
                                    onTap: null, // Background cards not clickable
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                }
                
                // Add all actual cards in the pile (for animation tracking)
                // Show top 5 cards (or all if less than 5) with opacity 1.0 for tracking
                final minVisibleCards = 5;
                final visibleCount = drawPile.length < minVisibleCards ? drawPile.length : minVisibleCards;
                final topVisibleIndex = drawPile.length - visibleCount;
                
                for (final entry in drawPile.asMap().entries) {
                  final index = entry.key;
                  final cardData = entry.value as Map<String, dynamic>? ?? {};
                  final cardId = cardData['cardId']?.toString() ?? 'draw_pile_empty';
                  final cardKey = _getOrCreateCardKey(cardId, 'draw_pile');
                  final isTopCard = index == topCardIndex;
                  final isVisible = index >= topVisibleIndex; // Top 5 cards (or all if less than 5)
                  
                  stackCards.add(
                    Positioned.fill(
                      child: Opacity(
                        opacity: isVisible ? 1.0 : 0.0, // Top 5 cards visible for tracking
                        child: CardWidget(
                          key: cardKey,
                          card: CardModel.fromMap(cardData),
                          dimensions: cardDimensions,
                          config: CardDisplayConfig.forDrawPile(),
                          showBack: true,
                          onTap: isTopCard ? _handleDrawPileClick : null, // Only top card clickable
                        ),
                      ),
                    ),
                  );
                }
                
                drawPileContent = SizedBox(
                  key: _drawPileKey,
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: stackCards,
                  ),
                );
              }
              
              // Wrap with animated glow effect when in drawing status
              if (isDrawingStatus && statusChipColor != null && _glowAnimation != null) {
                return AnimatedBuilder(
                  animation: _glowAnimation!,
                  builder: (context, child) {
                    final glowOpacity = _glowAnimation!.value;
                    final glowDecoration = _buildGlowDecoration(statusChipColor, glowOpacity);
                    return Container(
                      decoration: glowDecoration,
                      child: drawPileContent,
                    );
                  },
                );
              }
              
              return drawPileContent;
            },
          ),
        ],
      ),
      ),
    );
  }

  String? getClickedPileType() {
    return _clickedPileType;
  }

  void clearClickedPileType() {
    setState(() {
      _clickedPileType = null;
    });
  }

  void _handleDrawPileClick() async {
    final dutchGameState = _dutchGameState();
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
    
    if (currentPlayerStatus == 'drawing_card') {
      try {
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        if (currentGameId.isEmpty) {
          return;
        }
        final drawAction = PlayerAction.playerDraw(
          pileType: 'draw_pile',
          gameId: currentGameId,
        );
        await drawAction.execute();
        setState(() {
          _clickedPileType = 'draw_pile';
        });
      } catch (e) {
        // Game feedback: snackbars removed
      }
    } else {
      // Game feedback: snackbars removed
    }
  }

  // ========== Discard Pile Methods ==========

  /// Discard pile card size: scales with [availableWidth] (like opponent hand cards), clamped to [CardDimensions.MAX_CARD_WIDTH].
  Widget _buildDiscardPile({double? availableWidth, required Map<String, dynamic> board}) {
    if (LOGGING_SWITCH) {
      _logger.info('[GameBoard overflow] _buildDiscardPile: availableWidth=$availableWidth');
    }
    final discardPile = board['discardPile'] as List<dynamic>? ?? [];
    final hasCards = discardPile.isNotEmpty;
    
    return Container(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final Size cardDimensions = availableWidth != null && availableWidth > 0
                    ? _gameBoardPileCardDimensions(availableWidth)
                    : CardDimensions.getUnifiedDimensions();
                
                if (!hasCards) {
                // Empty discard pile. Key on card-sized SizedBox so animation bounds match card size.
                final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
                return SizedBox(
                  key: _discardPileKey,
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: CardWidget(
                    key: emptyKey,
                    card: CardModel(
                      cardId: 'discard_pile_empty',
                      rank: '?',
                      suit: '?',
                      points: 0,
                    ),
                    dimensions: cardDimensions,
                    config: CardDisplayConfig.forDiscardPile(),
                    showBack: true,
                    onTap: _handleDiscardPileClick,
                  ),
                );
              }
              
              // Render all cards in discard pile with stacking effect
              // Only the top card is visible and clickable, but all are tracked for animation
              final topCardIndex = discardPile.length - 1;
              final topCardData = discardPile[topCardIndex] as Map<String, dynamic>? ?? {};
              
              // Create stacking effect with 2 additional cards behind
              final stackCards = <Widget>[];
              
              // Add 2 background cards with rotation and offset for stacking effect
              for (int i = 0; i < 2; i++) {
                // Discard pile: 2° and 4° clockwise
                final rotation = (i + 1) * 2.0; // 2° and 4° (clockwise)
                final offset = (i + 1) * 1.5; // 1.5px and 3px offset
                // Add shadow to the last (bottom) card of the stack
                final isBottomCard = i == 1; // Second card is the bottom one
                stackCards.add(
                  Positioned.fill(
                    child: Transform.rotate(
                      angle: rotation * 3.14159 / 180, // Convert to radians
                      child: Transform.translate(
                        offset: Offset(-offset, -offset), // Negative X for discard pile
                        child: isBottomCard
                            ? Container(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Opacity(
                                  opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                  child: CardWidget(
                                    card: CardModel.fromMap(topCardData),
                                    dimensions: cardDimensions,
                                    config: CardDisplayConfig.forDiscardPile(),
                                    onTap: null, // Background cards not clickable
                                  ),
                                ),
                              )
                            : Opacity(
                                opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                child: CardWidget(
                                  card: CardModel.fromMap(topCardData),
                                  dimensions: cardDimensions,
                                  config: CardDisplayConfig.forDiscardPile(),
                                  onTap: null, // Background cards not clickable
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              }
              
              // Add all actual cards in the pile (for animation tracking)
              // Show top 5 cards (or all if less than 5) with opacity 1.0 for tracking
              final minVisibleCards = 5;
              final visibleCount = discardPile.length < minVisibleCards ? discardPile.length : minVisibleCards;
              final topVisibleIndex = discardPile.length - visibleCount;
              
              for (final entry in discardPile.asMap().entries) {
                final index = entry.key;
                final cardData = entry.value as Map<String, dynamic>? ?? {};
                final cardId = cardData['cardId']?.toString() ?? 'discard_pile_empty';
                final cardKey = _getOrCreateCardKey(cardId, 'discard_pile');
                final isTopCard = index == topCardIndex;
                final isVisible = index >= topVisibleIndex; // Top 5 cards (or all if less than 5)
                
                stackCards.add(
                  Positioned.fill(
                    child: Opacity(
                      opacity: isVisible ? 1.0 : 0.0, // Top 5 cards visible for tracking
                      child: CardWidget(
                        key: cardKey,
                        card: CardModel.fromMap(cardData),
                        dimensions: cardDimensions,
                        config: CardDisplayConfig.forDiscardPile(),
                        onTap: isTopCard ? _handleDiscardPileClick : null, // Only top card clickable
                      ),
                    ),
                  ),
                );
              }
              
              return SizedBox(
                key: _discardPileKey,
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: stackCards,
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }

  void _handleDiscardPileClick() async {
    final dutchGameState = _dutchGameState();
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'unknown';
    final gameState = dutchGameState['gameState'] as Map<String, dynamic>? ?? {};
    final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? true; // Default to true for backward compatibility
    
    // Block during same_rank_window and initial_peek phases - but only if collection mode is enabled
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && isClearAndCollect) {
      return;
    }
    
    // If collection is disabled (isClearAndCollect: false), silently ignore clicks during same_rank_window
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && !isClearAndCollect) {
      return; // Silently ignore - collection is disabled in this game mode
    }
    
    try {
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        return;
      }
      final collectAction = PlayerAction.collectFromDiscard(gameId: currentGameId);
      await collectAction.execute();
      setState(() {
        _clickedPileType = 'discard_pile';
      });
    } catch (e) {
      // Game feedback: snackbars removed
    }
  }

  // ========== Match Pot Methods ==========

  /// Full-width row at the bottom of the game board column: coin icon with amount beneath.
  /// Shown only when: not a practice game and user is not promotional tier.
  /// Amount vs '—' by isGameActive and gamePhase when shown.
  /// [rowWidth] is the full game board width (used to scale font/icon).
  Widget _buildMatchPotRow(double rowWidth, Map<String, dynamic> board) {
    final centerBoard = board['centerBoard'] as Map<String, dynamic>? ?? {};
    final matchPot = centerBoard['matchPot'] as int? ?? 0;
    final gamePhase = board['gamePhase']?.toString() ?? 'waiting';
    final isGameActive = board['isGameActive'] ?? false;
    final currentGameId = board['currentGameId']?.toString() ?? '';

    // Only show match pot if not a practice game
    final isPracticeGame = currentGameId.startsWith('practice_room_');
    if (isPracticeGame) {
      return const SizedBox.shrink();
    }

    // Hide match pot row for promotional tier (free play - no coins involved)
    final userStats = board['userStats'] as Map<String, dynamic>?;
    final subscriptionTier = userStats?['subscription_tier']?.toString() ?? 'promotional';
    if (subscriptionTier == 'promotional') {
      return const SizedBox.shrink();
    }

    final shouldShowPot = isGameActive && gamePhase != 'waiting';

    // Icon slightly larger than prior inline layout; amount below, smaller than icon scale.
    final iconSize = (rowWidth * 0.072).clamp(32.0, 76.0);
    final amountFontSize = (rowWidth * 0.045).clamp(18.0, 34.0);
    if (LOGGING_SWITCH) {
      _logger.info('[GameBoard overflow] _buildMatchPotRow: rowWidth=$rowWidth amountFontSize=$amountFontSize iconSize=$iconSize');
    }

    // Dedicated gold so it is not overridden by theme (e.g. Dutch theme accentColor2 is green)
    const potColor = AppColors.matchPotGold;
    final iconColor = shouldShowPot ? potColor : AppColors.textSecondary;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rowWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.monetization_on,
              size: iconSize,
              color: iconColor,
            ),
            const SizedBox(height: 4),
            Text(
              shouldShowPot ? matchPot.toString() : '—',
              style: AppTextStyles.headingLarge().copyWith(
                color: shouldShowPot ? potColor : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: amountFontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== My Hand Methods ==========

  /// Protect cardsToPeek data for 5 seconds (My Hand)
  void _protectMyHandCardsToPeek(List<dynamic> cardsToPeek) {
    _myHandCardsToPeekProtectionTimer?.cancel();
    _isMyHandCardsToPeekProtected = true;
    _protectedMyHandCardsToPeek = List<dynamic>.from(cardsToPeek);
    _myHandCardsToPeekProtectionTimer = Timer(Duration(seconds: 5), () {
      _clearMyHandCardsToPeekProtection();
    });
  }

  /// Clear cardsToPeek protection (My Hand)
  void _clearMyHandCardsToPeekProtection() {
    _isMyHandCardsToPeekProtected = false;
    _protectedMyHandCardsToPeek = null;
    _myHandCardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer = null;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildMyHand(Map<String, dynamic> board) {
    final myHand = board['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    final selectedIndex = myHand['selectedIndex'] ?? -1;
    final cardsToPeekFromState = board['myCardsToPeek'] as List<dynamic>? ?? [];
    final protectedCardsToPeek = board['protectedCardsToPeek'] as List<dynamic>?;
    
    // CRITICAL: Also check game_state.players (SSOT) for cardsToPeek — same data as full games tree, scoped in [board].
    final gameStateForPeek = board['boardGameState'] as Map<String, dynamic>? ?? {};
    final playersForPeek = gameStateForPeek['players'] as List<dynamic>? ?? [];
    
    // Get current user ID
    final loginStateForPeek = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserIdForPeek = loginStateForPeek['userId']?.toString() ?? '';
    
    // Find current user's player data in game state (SSOT)
    final myPlayerInGameState = playersForPeek.firstWhere(
      (p) => p is Map<String, dynamic> && p['id']?.toString() == currentUserIdForPeek,
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    
    final cardsToPeekFromGameState = myPlayerInGameState['cardsToPeek'] as List<dynamic>? ?? [];
    
    // CRITICAL: Clear protection if EITHER myCardsToPeek OR game state cardsToPeek is empty
    // This ensures cards don't remain visible after the 8-second timer clears them
    // Must defer setState() until after build completes
    final isCardsToPeekEmpty = cardsToPeekFromState.isEmpty && cardsToPeekFromGameState.isEmpty;
    if (isCardsToPeekEmpty && _isMyHandCardsToPeekProtected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Re-check state in callback to avoid race conditions
        final updatedState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final updatedCardsToPeek = updatedState['myCardsToPeek'] as List<dynamic>? ?? [];
        if (mounted && updatedCardsToPeek.isEmpty && _isMyHandCardsToPeekProtected) {
          _clearMyHandCardsToPeekProtection();
        }
      });
    }
    
    // Use widget-level timer instead of timestamp from state
    // When protectedCardsToPeek is set, start the 5-second protection timer
    if (protectedCardsToPeek != null && !_isMyHandCardsToPeekProtected) {
      _protectMyHandCardsToPeek(protectedCardsToPeek);
    }
    
    // Only protect if cardsToPeek is not empty (check both sources)
    if (!isCardsToPeekEmpty && !_isMyHandCardsToPeekProtected) {
      final cardsToCheck = cardsToPeekFromState.isNotEmpty ? cardsToPeekFromState : cardsToPeekFromGameState;
      final hasFullCardData = cardsToCheck.any((card) {
        if (card is Map<String, dynamic>) {
          final hasSuit = card.containsKey('suit') && card['suit'] != '?' && card['suit'] != null;
          final hasRank = card.containsKey('rank') && card['rank'] != '?' && card['rank'] != null;
          return hasSuit || hasRank;
        }
        return false;
      });
      if (hasFullCardData) {
        _protectMyHandCardsToPeek(cardsToCheck);
      }
    }
    
    // Use protected cards if available, otherwise use state (prioritize state over game state)
    final cardsToPeek = _isMyHandCardsToPeekProtected && _protectedMyHandCardsToPeek != null
        ? _protectedMyHandCardsToPeek!
        : (cardsToPeekFromState.isNotEmpty ? cardsToPeekFromState : cardsToPeekFromGameState);
    
    final isGameActive = board['isGameActive'] ?? false;
    final isMyTurn = board['isMyTurn'] ?? false;
    final playerStatus = _getCurrentUserStatus(); // Use same source as status chip
    final currentGameId = board['currentGameId']?.toString() ?? '';
    final gameState = board['boardGameState'] as Map<String, dynamic>? ?? {};
    final finalRoundActive = gameState['finalRoundActive'] as bool? ?? false;
    final finalRoundCalledBy = gameState['finalRoundCalledBy']?.toString();
    // Get timer from game_state timerConfig (added during game initialization)
    // Safely convert Map<String, dynamic> to Map<String, int>
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final phase = gameState['phase'] as String?;
    // Calculate timer based on phase or status using timerConfig from game_state
    // Priority: Status is more specific than phase, so check status first
    int? turnTimeLimit;
    
    // Check status first (more specific than phase for player actions)
    if (playerStatus.isNotEmpty) {
      switch (playerStatus) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 15;
          break;
        case 'drawing_card':
          turnTimeLimit = timerConfig['drawing_card'] ?? 20;
          break;
        case 'playing_card':
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          turnTimeLimit = timerConfig['same_rank_window'] ?? 10;
          break;
        case 'queen_peek':
          turnTimeLimit = timerConfig['queen_peek'] ?? 15;
          break;
        case 'jack_swap':
          turnTimeLimit = timerConfig['jack_swap'] ?? 20;
          break;
        case 'peeking':
          turnTimeLimit = timerConfig['peeking'] ?? 10;
          break;
        case 'waiting':
          turnTimeLimit = timerConfig['waiting'] ?? 0;
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (turnTimeLimit == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 15;
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          turnTimeLimit = timerConfig['same_rank_window'] ?? 10;
          break;
        case 'queen_peek_window':
          turnTimeLimit = timerConfig['queen_peek'] ?? 15;
          break;
        case 'special_play_window':
          turnTimeLimit = timerConfig['jack_swap'] ?? 20;
          break;
        default:
          turnTimeLimit = timerConfig['default'] ?? 30;
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    turnTimeLimit ??= 30;
    
    // Ensure turnTimeLimit is valid (not 0, not negative, not NaN) to prevent division by zero in timer widget
    if (turnTimeLimit <= 0 || !turnTimeLimit.isFinite) {
      turnTimeLimit = 30; // Safe default
    }
    
    // Games map SSOT for "me" (practice: `practice_session_<userId>` even when getCurrentUserId is login UUID).
    final myBoardPlayerId = _myBoardPlayerId(board);
    
    // Get current user's player data from game_state to retrieve profile picture
    // Profile picture is fetched when player joins and stored in player['profile_picture']
    final players = gameState['players'] as List<dynamic>? ?? [];
    Map<String, dynamic>? currentUserPlayer;
    try {
      currentUserPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['id']?.toString() == myBoardPlayerId,
      );
    } catch (e) {
      // Player not found, will use fallback to StateManager
      currentUserPlayer = null;
    }
    final currentUserProfilePicture = currentUserPlayer?['profile_picture']?.toString();
    
    final hasPlayerCalledFinalRound = gameState['players'] != null
        ? (gameState['players'] as List<dynamic>?)
            ?.any((p) => p is Map<String, dynamic> && 
                p['id']?.toString() == myBoardPlayerId && 
                p['hasCalledFinalRound'] == true) ?? false
        : false;
    
    final actionError = board['actionError'] as Map<String, dynamic>?;
    if (actionError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        StateManager().updateModuleState('dutch_game', {
          'actionError': null,
        });
      });
    }
    
    // Reset selectedIndex and jack swap selections only when state shows this player moved from jack_swap to waiting
    // (swap succeeded or timer expired — same as queen peek; do NOT advance on jack_swap_error / fail)
    if (_previousPlayerStatus == 'jack_swap' && playerStatus == 'waiting') {
      if (LOGGING_SWITCH) {
        _logger.info('🃏 UnifiedGameBoardWidget: Status changed from jack_swap to waiting - resetting selectedIndex');
      }
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (currentGameId.isNotEmpty && currentGames.containsKey(currentGameId)) {
        final currentGame = Map<String, dynamic>.from(currentGames[currentGameId]);
        currentGame['selectedCardIndex'] = -1;
        currentGames[currentGameId] = currentGame;
        // Also reset in myHand slice
        final myHand = Map<String, dynamic>.from(currentState['myHand'] as Map<String, dynamic>? ?? {});
        myHand['selectedIndex'] = -1;
        // Update both in a single state update
        StateManager().updateModuleState('dutch_game', {
          'games': currentGames,
          'myHand': myHand,
        });
      }
      // Also clear jack swap selections in PlayerAction
      PlayerAction.resetJackSwapSelections();
    }
    
    // Update previous status for next check
    _previousPlayerStatus = playerStatus;
    
    if (playerStatus != 'initial_peek' && _initialPeekSelectionCount > 0) {
      _initialPeekSelectionCount = 0;
      _initialPeekSelectedCardIds.clear();
    }
    
    // For timer color, always get the status chip color (including same_rank_window)
    final timerColor = _getStatusChipColor(playerStatus);
    final myUserStats = _dutchGameState()['userStats'] as Map<String, dynamic>? ?? {};
    final myInventory = myUserStats['inventory'] as Map<String, dynamic>? ?? {};
    final myCosmetics = myInventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final myEquipped = myCosmetics['equipped'] as Map<String, dynamic>? ?? {};
    final myEquippedCardBackId = myEquipped['card_back_id']?.toString() ?? '';
    final equippedLabel = _friendlyCardBackLabel(myEquippedCardBackId);

    final Widget? myFirstCardHandHud = cards.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playerStatus != 'waiting')
                CircularTimerWidget(
                  key: ValueKey('timer_myhand_${playerStatus}'),
                  durationSeconds: turnTimeLimit,
                  size: _kHudRingOuter,
                  strokeWidth: _kHudRingStroke,
                  color: timerColor,
                  backgroundColor: AppColors.surfaceVariant,
                  centerChild: _buildPlayerProfilePicture(
                    _myBoardPlayerId(board),
                    profilePictureUrl: currentUserProfilePicture,
                    diameter: _kHudAvatarInRing,
                  ),
                )
              else
                _buildPlayerProfilePicture(
                  _myBoardPlayerId(board),
                  profilePictureUrl: currentUserProfilePicture,
                ),
            ],
          );
    
    final highlightMyHandSection = isGameActive && isMyTurn;
    // My hand section: column with (1) header row = You + status chip (+ optional Call Final Round), (2) cards with HUD on index 0
    return Container(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppPadding.mediumPadding.left),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: label + status chip (+ optional Call Final Round). Profile + timer sit on first card.
            Row(
              children: [
                Text(
                  'You',
                  style: AppTextStyles.headingSmall(),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showInPlayCustomizeModal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderDefault),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          equippedLabel,
                          style: AppTextStyles.overline().copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (isGameActive && isMyTurn && (playerStatus == 'same_rank_window') && !finalRoundActive && !hasPlayerCalledFinalRound && !_callFinalRoundTappedPending) ...[
                  GestureDetector(
                    onTap: () => _handleCallFinalRound(context, currentGameId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.callFinalRoundChipBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag,
                            size: 12,
                            color: AppColors.textOnAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Call Final Round',
                            style: AppTextStyles.bodySmall().copyWith(
                              color: AppColors.textOnAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (finalRoundActive || _callFinalRoundTappedPending) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.callFinalRoundChipBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (finalRoundActive && finalRoundCalledBy == _myBoardPlayerId(board))
                              ? Icons.flag
                              : Icons.flag_outlined,
                          size: 12,
                          color: AppColors.textOnAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (finalRoundActive && finalRoundCalledBy == _myBoardPlayerId(board))
                              ? 'You Called Final Round'
                              : 'Final Round Active',
                          style: AppTextStyles.bodySmall().copyWith(
                            color: AppColors.textOnAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (playerStatus != 'unknown')
                  PlayerStatusChip(
                    playerId: _myBoardPlayerId(board),
                    size: PlayerStatusChipSize.small,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Row 2: cards only, taking all available horizontal space
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(highlightMyHandSection ? 4 : 0),
              decoration: BoxDecoration(
                color: highlightMyHandSection ? timerColor.withOpacity(0.12) : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: highlightMyHandSection ? timerColor : Colors.transparent,
                  width: highlightMyHandSection ? 2.0 : 0.0,
                ),
                boxShadow: highlightMyHandSection
                    ? [
                        BoxShadow(
                          color: timerColor.withOpacity(0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: cards.isEmpty
                  ? _buildMyHandEmptyHand()
                  : SizedBox(
                      width: double.infinity,
                      child: _buildMyHandCardsGrid(
                        cards,
                        cardsToPeek,
                        selectedIndex,
                        board,
                        isMyTurn,
                        firstCardHandHud: myFirstCardHandHud,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandEmptyHand() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'No cards in hand',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandCardsGrid(
    List<dynamic> cards,
    List<dynamic> cardsToPeek,
    int selectedIndex,
    Map<String, dynamic> board,
    bool isMyTurn, {
    Widget? firstCardHandHud,
  }) {
    return LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
            // Ensure containerWidth is valid before calculations
            if (containerWidth <= 0 || !containerWidth.isFinite) {
              return const SizedBox.shrink();
            }

            final currentPlayerStatus = _getCurrentUserStatus();
            final drawnCard = board['myDrawnCard'] as Map<String, dynamic>?;
            final drawnCardId = drawnCard?['cardId']?.toString();
            final bgsInner = board['boardGameState'] as Map<String, dynamic>? ?? {};
            final players = bgsInner['players'] as List<dynamic>? ?? [];
            final myPid = _myBoardPlayerId(board);
            
            List<dynamic> myCollectionRankCards = [];
            for (var player in players) {
              if (player is Map<String, dynamic> && player['id']?.toString() == myPid) {
                myCollectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
                break;
              }
            }
            
            final collectionRankCardIds = myCollectionRankCards
                .where((c) => c is Map<String, dynamic>)
                .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
                .where((id) => id != null)
                .toSet();
            
            Map<String, Widget> collectionRankWidgets = {};
            
            final cardPadding = containerWidth * 0.02;
            final cardDimensions = _adaptiveCardSize(
              availableWidth: containerWidth,
              slots: cards.length,
              slotGap: cardPadding,
            );
            final cardHeight = cardDimensions.height;
            final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;

            Widget applyMyFirstCardHud(int index, Widget slotContent) {
              final hud = firstCardHandHud;
              if (index != 0 || hud == null) return slotContent;
              return _stackHandHudOnFirstCardSlot(
                cardSlot: slotContent,
                corner: _HandHudCorner.myHandTopLeft,
                hud: hud,
              );
            }
            
            for (int i = 0; i < cards.length; i++) {
              final card = cards[i];
              if (card == null) continue;
              final cardMap = card as Map<String, dynamic>;
              final cardId = cardMap['cardId']?.toString();
              if (cardId == null) continue;
              final isSelected = i == selectedIndex;
              final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
              Map<String, dynamic>? peekedCardData;
              if (cardsToPeek.isNotEmpty) {
                for (var peekedCard in cardsToPeek) {
                  if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                    peekedCardData = peekedCard;
                    break;
                  }
                }
              }
              Map<String, dynamic>? collectionRankCardData;
              if (myCollectionRankCards.isNotEmpty) {
                for (var collectionCard in myCollectionRankCards) {
                  if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                    collectionRankCardData = collectionCard;
                    break;
                  }
                }
              }
              if (collectionRankCardData != null) {
                final cardDataToUse = isDrawnCard && drawnCard != null
                    ? drawnCard 
                    : (peekedCardData ?? collectionRankCardData);
                // Use calculated dimensions from LayoutBuilder
                final playerId = myPid;
                final cardKey = _getOrCreateCardKey('${playerId}_$i', 'my_hand');
                final cardWidget = _buildMyHandCardWidget(
                  cardDataToUse,
                  isSelected,
                  isDrawnCard,
                  false,
                  i,
                  cardMap,
                  cardKey,
                  cardDimensions,
                  currentPlayerStatus: currentPlayerStatus,
                  myDrawnCardFromBoard: drawnCard,
                );
                collectionRankWidgets[cardId] = cardWidget;
              }
            }
        
        // Get current player status for glow effect (using same source as status chip)
        final currentPlayerStatusForGlow = _getCurrentUserStatus();
        
        // Build all card widgets with fixed dimensions
        List<Widget> cardWidgets = [];
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          
          // Handle null cards (blank slots from same-rank plays)
          if (card == null) {
            final playerId = myPid;
            final blankSlotKey = _getOrCreateCardKey('${playerId}_$index', 'my_hand');
            cardWidgets.add(
              Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: applyMyFirstCardHud(
                  index,
                  Container(
                    key: blankSlotKey,
                    child: _buildBlankCardSlot(cardDimensions),
                  ),
                ),
              ),
            );
            continue;
          }
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final isSelected = index == selectedIndex;
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          
          // Check if this card is in cardsToPeek (peeked cards have full data)
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          
          // Check if this card is in player's collection_rank_cards
          Map<String, dynamic>? collectionRankCardData;
          bool isCollectionRankCard = false;
          if (cardId != null && myCollectionRankCards.isNotEmpty) {
            for (var collectionCard in myCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                isCollectionRankCard = true;
                break;
              }
            }
          }
          
          // Determine which data to use (priority: drawn card > peeked card > collection rank card > ID-only hand card)
          // For drawn cards, ensure we have full data (rank and suit not '?')
          Map<String, dynamic> cardDataToUse;
          if (isDrawnCard && drawnCard != null) {
            // Validate drawn card has full data
            final hasFullData = drawnCard.containsKey('rank') && 
                               drawnCard['rank'] != null && 
                               drawnCard['rank'] != '?' &&
                               drawnCard.containsKey('suit') && 
                               drawnCard['suit'] != null && 
                               drawnCard['suit'] != '?';
            if (hasFullData) {
              cardDataToUse = drawnCard;
            } else {
              // Drawn card data is incomplete, fall back to other sources
              cardDataToUse = peekedCardData ?? collectionRankCardData ?? cardMap;
            }
          } else {
            cardDataToUse = peekedCardData ?? collectionRankCardData ?? cardMap;
          }
          
          // If this is a collection rank card, render the stack (only once, at the first collection card)
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            // Check if this is the first collection card in the hand
            bool isFirstCollectionCard = true;
            for (int i = 0; i < index; i++) {
              final prevCard = cards[i];
              if (prevCard != null && prevCard is Map<String, dynamic>) {
                final prevCardId = prevCard['cardId']?.toString();
                if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                  isFirstCollectionCard = false;
                  break;
                }
              }
            }
            
            if (isFirstCollectionCard) {
              // This is the first collection card, render the entire stack
              // One key for the whole stack (on the container) so bounds = stack position for all collection indices
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in myCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    // No key on inner cards; stack container holds the key for bounds
                    final collectionCardWidget = _buildMyHandCardWidget(
                      collectionCard,
                      false,
                      false,
                      false,
                      index,
                      collectionCard,
                      null, // no key - stack container has the key for bounds
                      cardDimensions,
                      currentPlayerStatus: currentPlayerStatusForGlow,
                    );
                    orderedCollectionWidgets.add(collectionCardWidget);
                  }
                }
              }
              
              final cardWidth = cardDimensions.width;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              final stackKey = _getOrCreateCardKey('${myPid}_$index', 'my_hand');
              
              final stackWidget = Container(
                key: stackKey,
                width: cardWidth,
                height: stackHeight,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: orderedCollectionWidgets.asMap().entries.map((entry) {
                    return Positioned(
                      left: 0,
                      top: entry.key * stackOffset,
                      child: entry.value,
                    );
                  }).toList(),
                ),
              );
              
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(
                    right: cardPadding,
                  ),
                  child: applyMyFirstCardHud(
                    index,
                    _wrapHandSlotAnimMask(myPid, index, stackWidget),
                  ),
                ),
              );
            }
            // Skip non-first collection cards (they're already in the stack)
          } else {
            // Normal card rendering (non-collection rank)
            if (cardId == null) {
              continue;
            }
            final playerId = myPid;
            final cardKey = _getOrCreateCardKey('${playerId}_$index', 'my_hand');
            final cardWidget = _buildMyHandCardWidget(
              cardDataToUse, 
              isSelected, 
              isDrawnCard, 
              false, 
              index, 
              cardMap, 
              cardKey,
              cardDimensions,
              currentPlayerStatus: currentPlayerStatusForGlow,
              myDrawnCardFromBoard: drawnCard,
            );
            
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(
                    right: cardPadding,
                  ),
                  child: applyMyFirstCardHud(
                    index,
                    _wrapHandSlotAnimMask(playerId, index, cardWidget),
                  ),
                ),
              );
            }
          }

          if (LOGGING_SWITCH) {
            final approxTotalRowW =
                cardWidgets.length * (cardDimensions.width + cardPadding);
            _logger.info(
              '[MyHandLayout] realRow isMyTurn=$isMyTurn cardsLen=${cards.length} '
              'slots=${cardWidgets.length} '
              'approxTotalRowW=${approxTotalRowW.toStringAsFixed(1)} containerW=${containerWidth.toStringAsFixed(1)} '
              'cardW=${cardDimensions.width.toStringAsFixed(1)}',
            );
          }

          return SizedBox(
            width: containerWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: cardWidgets,
            ),
          );
          },
    );
  }

  /// `players[].id` for the human row (SSOT for `game_animation` [`owner_id`] and games map).
  /// In practice, [getCurrentUserId] can resolve to login UUID when `practiceUser` is unset while
  /// the embedded backend still uses `practice_session_<userId>` as [players].id — that
  /// mismatch breaks [DutchAnimRuntime] slot rects vs overlay [rectFor].
  String _myBoardPlayerId(Map<String, dynamic> board) {
    final players =
        (board['boardGameState'] as Map<String, dynamic>? ?? {})['players'] as List<dynamic>? ?? [];
    for (final p in players) {
      if (p is! Map<String, dynamic>) continue;
      if (p['isHuman'] == true) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty) return id;
      }
    }
    final cached = DutchEventHandlerCallbacks.getCurrentUserId();
    for (final p in players) {
      if (p is! Map<String, dynamic>) continue;
      final id = p['id']?.toString() ?? '';
      if (id.isNotEmpty && id == cached) return id;
    }
    return cached;
  }

  Future<void> _showInPlayCustomizeModal() async {
    if (LOGGING_SWITCH) {
      _logger.info('🧭 UnifiedGameBoardWidget: opening in-play customize modal');
    }
    List<Map<String, dynamic>> catalog = const [];
    Map<String, dynamic> inventory = const {};

    Future<void> refresh(StateSetter setModalState) async {
      if (LOGGING_SWITCH) {
        _logger.info('🧭 UnifiedGameBoardWidget: refresh in-play customize modal data');
      }
      catalog = await DutchGameHelpers.getShopCatalog();
      inventory = await DutchGameHelpers.fetchInventory() ?? {};
      if (LOGGING_SWITCH) {
        _logger.info('🧭 UnifiedGameBoardWidget: modal data loaded catalog=${catalog.length}');
      }
      setModalState(() {});
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Customize',
      barrierColor: AppColors.black.withValues(alpha: AppOpacity.instructionsModalBarrier),
      pageBuilder: (context, _, __) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              bool isOwned(Map<String, dynamic> item) {
                final type = item['item_type']?.toString() ?? '';
                final id = item['item_id']?.toString() ?? '';
                final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
                final ownedBacks = (cosmetics['owned_card_backs'] as List<dynamic>? ?? const [])
                    .map((e) => e.toString())
                    .toSet();
                final ownedTables = (cosmetics['owned_table_designs'] as List<dynamic>? ?? const [])
                    .map((e) => e.toString())
                    .toSet();
                if (type == 'card_back') return ownedBacks.contains(id);
                if (type == 'table_design') return ownedTables.contains(id);
                return false;
              }

              bool isEquipped(Map<String, dynamic> item) {
                final type = item['item_type']?.toString() ?? '';
                final id = item['item_id']?.toString() ?? '';
                final equipped =
                    (inventory['cosmetics'] as Map<String, dynamic>? ?? const {})['equipped']
                        as Map<String, dynamic>? ??
                    const {};
                if (type == 'card_back') return equipped['card_back_id']?.toString() == id;
                if (type == 'table_design') return equipped['table_design_id']?.toString() == id;
                return false;
              }

              final cosmeticItems = catalog.where((i) {
                final t = i['item_type']?.toString() ?? '';
                return t == 'card_back' || t == 'table_design';
              }).toList();

              if (catalog.isEmpty && inventory.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  refresh(setModalState);
                });
              }

              return Material(
                color: Colors.transparent,
                child: Container(
                  margin: EdgeInsets.fromLTRB(
                    AppPadding.defaultPadding.left,
                    0,
                    AppPadding.defaultPadding.right,
                    110,
                  ),
                  constraints: const BoxConstraints(maxHeight: 320),
                  decoration: BoxDecoration(
                    color: AppColors.widgetContainerBackground,
                    borderRadius: AppBorderRadius.largeRadius,
                    border: Border.all(color: AppColors.borderDefault),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withValues(alpha: AppOpacity.shadow),
                        blurRadius: AppSizes.shadowBlur,
                        offset: AppSizes.shadowOffset,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: AppBorderRadius.largeRadius,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.accentColor,
                          ),
                          child: Padding(
                            padding: AppPadding.cardPadding,
                            child: Text(
                              'Quick Customize',
                              style: AppTextStyles.headingSmall(color: AppColors.textOnAccent),
                            ),
                          ),
                        ),
                        if (cosmeticItems.where(isOwned).isEmpty)
                          Padding(
                            padding: AppPadding.mediumPadding,
                            child: Text(
                              'No owned packs yet.',
                              style: AppTextStyles.bodySmall(color: AppColors.lightGray),
                            ),
                          ),
                        for (final item in cosmeticItems)
                          if (isOwned(item))
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                AppPadding.mediumPadding.left,
                                0,
                                AppPadding.mediumPadding.right,
                                AppPadding.smallPadding.bottom,
                              ),
                              child: Container(
                                padding: AppPadding.cardPadding,
                                decoration: BoxDecoration(
                                  color: AppColors.scaffoldBackgroundColor.withValues(alpha: 0.45),
                                  borderRadius: AppBorderRadius.mediumRadius,
                                  border: Border.all(
                                    color: isEquipped(item)
                                        ? AppColors.accentColor.withValues(alpha: 0.45)
                                        : AppColors.borderDefault,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['display_name']?.toString() ?? 'Item',
                                        style: AppTextStyles.bodySmall(color: AppColors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isEquipped(item))
                                      FilledButton(
                                        onPressed: () async {
                                          final type = item['item_type']?.toString() ?? '';
                                          final slot =
                                              type == 'card_back' ? 'card_back' : 'table_design';
                                          await DutchGameHelpers.equipCosmetic(
                                            slot: slot,
                                            cosmeticId: item['item_id']?.toString() ?? '',
                                          );
                                          await refresh(setModalState);
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.accentColor,
                                          foregroundColor: AppColors.textOnAccent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: AppBorderRadius.smallRadius,
                                          ),
                                          textStyle: AppTextStyles.label(
                                            color: AppColors.textOnAccent,
                                          ),
                                        ),
                                        child: const Text('Use'),
                                      ),
                                    if (isEquipped(item))
                                      OutlinedButton(
                                        onPressed: () async {
                                          final type = item['item_type']?.toString() ?? '';
                                          final slot =
                                              type == 'card_back' ? 'card_back' : 'table_design';
                                          await DutchGameHelpers.equipCosmetic(
                                            slot: slot,
                                            cosmeticId: '',
                                          );
                                          await refresh(setModalState);
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.white,
                                          side: BorderSide(
                                            color: AppColors.accentContrast.withValues(alpha: 0.7),
                                            width: 1.5,
                                          ),
                                          backgroundColor:
                                              AppColors.accentContrast.withValues(alpha: 0.18),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: AppBorderRadius.smallRadius,
                                          ),
                                          textStyle: AppTextStyles.label(color: AppColors.white),
                                        ),
                                        child: const Text('Unuse'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Get current user's status from the same source as PlayerStatusChip
  /// This ensures consistency between status chip and card lighting
  String _getCurrentUserStatus() {
    final dutchGameState = _dutchGameState();
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    return myHand['playerStatus']?.toString() ?? 'unknown';
  }

  Future<void> _handleCallFinalRound(BuildContext context, String gameId) async {
    if (LOGGING_SWITCH) {
      _logger.info('🎯 MyHandWidget - _handleCallFinalRound called with gameId: $gameId');
    }
    if (_isProcessingAction) {
      if (LOGGING_SWITCH) {
        _logger.info('🚫 MyHandWidget - Action already in progress, ignoring call final round');
      }
      return;
    }
    if (gameId.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ MyHandWidget - gameId is empty');
      }
      return;
    }
    try {
      setState(() {
        _isProcessingAction = true;
        _callFinalRoundTappedPending = true; // Show "Final Round Active" immediately
      });
      if (LOGGING_SWITCH) {
        _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true (call final round)');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🎯 MyHandWidget - Creating PlayerAction.callFinalRound with gameId: $gameId');
      }
      final callFinalRoundAction = PlayerAction.callFinalRound(gameId: gameId);
      if (LOGGING_SWITCH) {
        _logger.info('🎯 MyHandWidget - Executing callFinalRoundAction...');
      }
      await callFinalRoundAction.execute();
      if (LOGGING_SWITCH) {
        _logger.info('✅ MyHandWidget - callFinalRoundAction.execute() completed');
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          if (LOGGING_SWITCH) {
            _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round)');
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingAction = false;
          _callFinalRoundTappedPending = false; // Restore button on failure
        });
        if (LOGGING_SWITCH) {
          _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round error)');
        }
      }
    }
  }

  void _handleMyHandCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    if (_isProcessingAction) {
      if (LOGGING_SWITCH) {
        _logger.info('🚫 MyHandWidget - Action already in progress, ignoring card selection');
      }
      return;
    }
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = _getCurrentUserStatus();
    if (LOGGING_SWITCH) {
      _logger.info('🎯 MyHandWidget - Card tapped: ${card['cardId']}, Status: $currentPlayerStatus');
    }
      
    if (currentPlayerStatus == 'jack_swap') {
      if (LOGGING_SWITCH) {
        _logger.info('🃏 MyHandWidget: Status is jack_swap - cards are interactive');
      }
    }
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window' ||
        currentPlayerStatus == 'initial_peek') {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 MyHandWidget - Status matches allowed statuses: $currentPlayerStatus');
      }
      final updatedMyHand = {
        ...currentMyHand,
        'selectedIndex': index,
        'selectedCard': card,
      };
      StateManager().updateModuleState('dutch_game', {
        'myHand': updatedMyHand,
      });
      _startSelectedOverlayClearTimer();
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (LOGGING_SWITCH) {
        _logger.info('🎮 MyHandWidget - currentGameId: $currentGameId');
      }
      if (currentGameId.isEmpty) {
        return;
      }
      try {
        if (LOGGING_SWITCH) {
          _logger.info('🎮 MyHandWidget - Inside try block, checking status: $currentPlayerStatus');
        }
        if (currentPlayerStatus == 'same_rank_window') {
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - Status is same_rank_window');
          }
          final sameRankAction = PlayerAction.sameRankPlay(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await sameRankAction.execute();
        } else if (currentPlayerStatus == 'jack_swap') {
          final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
          if (LOGGING_SWITCH) {
            _logger.info('🃏 MyHandWidget: Card tapped during jack_swap - Card: ${card['cardId']}, Player: $currentUserId, Game: $currentGameId');
          }
          if (LOGGING_SWITCH) {
            _logger.info('🃏 MyHandWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}');
          }
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentUserId,
            gameId: currentGameId,
          );
          final selectionCount = PlayerAction.getJackSwapSelectionCount();
          if (LOGGING_SWITCH) {
            _logger.info('🃏 MyHandWidget: After selection, jack swap count: $selectionCount');
          }
          if (selectionCount == 1) {
            // Game feedback: snackbars removed
          } else if (selectionCount == 2) {
            // Game feedback: snackbars removed
          }
        } else if (currentPlayerStatus == 'queen_peek') {
          final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
          final queenPeekAction = PlayerAction.queenPeek(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
            ownerId: currentUserId,
          );
          await queenPeekAction.execute();
        } else if (currentPlayerStatus == 'initial_peek') {
          final cardId = card['cardId']?.toString() ?? '';
          if (cardId.isEmpty) {
            return;
          }

          // Check if we're in demo mode
          final games = currentState['games'] as Map<String, dynamic>? ?? {};
          final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
          final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
          final gameType = gameState['gameType']?.toString() ?? 'normal';
          final isDemoMode = gameType == 'demo';

          if (isDemoMode) {
            // Demo mode: use DemoFunctionality to show card details
            if (LOGGING_SWITCH) {
              _logger.info('🎮 MyHandWidget: Demo mode - adding card to initial peek via DemoFunctionality');
            }
            
            // Check if already selected (using DemoFunctionality's tracking)
            final demoSelectedIds = DemoFunctionality.instance.getInitialPeekSelectedCardIds();
            if (demoSelectedIds.contains(cardId)) {
              return;
            }

            // Add card to initial peek (this will update myCardsToPeek in state)
            final selectedCount = await DemoFunctionality.instance.addCardToInitialPeek(cardId);

            // If 2 cards selected, complete the initial peek
            if (selectedCount == 2) {
              await Future.delayed(Duration(milliseconds: 500));
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: DemoFunctionality.instance.getInitialPeekSelectedCardIds(),
              );
              await completedInitialPeekAction.execute();
              // Note: DemoFunctionality._handleCompletedInitialPeek already clears the tracking set
              // Cards remain visible in myCardsToPeek so user can see both cards they peeked at
            }
          } else {
            // Normal mode: use existing logic
          if (_initialPeekSelectedCardIds.contains(cardId)) {
            return;
          }
          if (_initialPeekSelectionCount < 2) {
            _initialPeekSelectedCardIds.add(cardId);
            _initialPeekSelectionCount++;
            if (_initialPeekSelectionCount == 2) {
              await Future.delayed(Duration(milliseconds: 500));
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: _initialPeekSelectedCardIds,
              );
              await completedInitialPeekAction.execute();
              _initialPeekSelectionCount = 0;
              _initialPeekSelectedCardIds.clear();
            }
          } else {
            // Game feedback: snackbars removed
            }
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - Entering else block for playing_card status');
          }
          setState(() {
            _isProcessingAction = true;
          });
          if (LOGGING_SWITCH) {
            _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true');
          }
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - About to execute playerPlayCard: cardId=${card['cardId']}, gameId=$currentGameId');
          }
          try {
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
            if (LOGGING_SWITCH) {
              _logger.info('🎮 MyHandWidget - Calling playAction.execute()');
            }
          await playAction.execute();
          } catch (e, stackTrace) {
            if (LOGGING_SWITCH) {
              _logger.error('❌ MyHandWidget - Error executing playAction: $e');
            }
            if (LOGGING_SWITCH) {
              _logger.error('❌ MyHandWidget - Stack trace: $stackTrace');
            }
            rethrow;
          }
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - playAction.execute() completed');
          }
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isProcessingAction = false;
              });
              if (LOGGING_SWITCH) {
                _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false');
              }
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          if (LOGGING_SWITCH) {
            _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (error case)');
          }
        }
      }
    } else {
      // Game feedback: snackbars removed
    }
  }


  Widget _buildMyHandCardWidget(
    Map<String, dynamic> card,
    bool isSelected,
    bool isDrawnCard,
    bool isCollectionRankCard,
    int index,
    Map<String, dynamic> cardMap,
    GlobalKey? cardKey,
    Size cardDimensions, {
    String? currentPlayerStatus,
    Map<String, dynamic>? myDrawnCardFromBoard,
  }) {
    // For drawn cards in user's hand, always show face up
    // Ensure card has full data - if not, try to get it from the cardMap or myDrawnCard in state
    Map<String, dynamic> cardDataToUse = card;
    if (isDrawnCard) {
      // For drawn cards, we MUST have full data (rank, suit, points)
      // Check if current card data is incomplete
      final hasIncompleteData = !card.containsKey('rank') || 
                                card['rank'] == null || 
                                card['rank'] == '?' ||
                                !card.containsKey('suit') || 
                                card['suit'] == null || 
                                card['suit'] == '?';
      
      if (hasIncompleteData) {
        // Try to get full data from cardMap first
        if (cardMap.containsKey('rank') && 
            cardMap['rank'] != null && 
            cardMap['rank'] != '?' &&
            cardMap.containsKey('suit') && 
            cardMap['suit'] != null && 
            cardMap['suit'] != '?') {
          cardDataToUse = cardMap;
        } else {
          // Last resort: drawn card from board snapshot, then live dutch_game state
          final myDrawnCard = myDrawnCardFromBoard ??
              (_dutchGameState()['myDrawnCard'] as Map<String, dynamic>?);
          if (myDrawnCard != null && 
              myDrawnCard.containsKey('rank') && 
              myDrawnCard['rank'] != null && 
              myDrawnCard['rank'] != '?' &&
              myDrawnCard.containsKey('suit') && 
              myDrawnCard['suit'] != null && 
              myDrawnCard['suit'] != '?') {
            cardDataToUse = myDrawnCard;
          }
        }
      }
    }
    
    final cardModel = CardModel.fromMap(cardDataToUse);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    // For drawn cards in user's hand, show face up ONLY if we have complete data
    // If data is still incomplete after all fallbacks, show back to avoid blank white card
    // For other cards, show back if face down or missing full data
    final hasCompleteData = cardModel.hasFullData && 
                           cardModel.rank != '?' && 
                           cardModel.suit != '?';
    final shouldShowBack = isDrawnCard 
        ? !hasCompleteData  // Show back if data is incomplete
        : (cardModel.isFaceDown || !cardModel.hasFullData);
    final userStats = _dutchGameState()['userStats'] as Map<String, dynamic>? ?? {};
    final inventory = userStats['inventory'] as Map<String, dynamic>? ?? {};
    final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
    final myCardBackId = equipped['card_back_id']?.toString();
    
    // Use provided cardDimensions (may be rescaled to fit container)
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forMyHand(),
      showBack: shouldShowBack,
      ownerCardBackId: myCardBackId,
      isSelected: isSelected,
      onTap: () => _handleMyHandCardSelection(context, index, cardMap),
    );
    
    // Apply glow effect based on current player status
    final glowColor = currentPlayerStatus != null 
        ? _getGlowColorForCards(currentPlayerStatus, true) 
        : null;
    
    if (glowColor != null && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) {
          final glowOpacity = _glowAnimation!.value;
          final glowDecoration = _buildGlowDecoration(glowColor, glowOpacity);
          return Container(
            decoration: glowDecoration,
            child: cardWidget,
          );
        },
      );
    }
    
    return cardWidget;
  }

  /// Build circular profile picture widget
  /// Size is 1.5x the status chip height (small size)
  /// Shows user's profile picture if available, otherwise shows default icon
  /// [playerId] The player's session ID
  /// [profilePictureUrl] Optional profile picture URL (for opponents from player data)
  /// [diameter] Circle size; use [_kHudAvatarInRing] when nested inside [CircularTimerWidget].
  Widget _buildPlayerProfilePicture(String playerId, {String? profilePictureUrl, double diameter = 28.0}) {
    final double profilePictureSize = diameter;
    
    // Get profile picture URL from game_state (SSOT) if not provided
    if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
      final dutchGameState = _dutchGameState();
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final gameData = games[currentGameId] as Map<String, dynamic>?;
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      final players = gameState?['players'] as List<dynamic>? ?? [];
      
      // Find player in game_state by playerId
      try {
        final player = players.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id']?.toString() == playerId,
        );
        profilePictureUrl = player['profile_picture']?.toString();
      } catch (e) {
        // Player not found in game_state, profilePictureUrl remains null
      }
    }
    
    // If we have a profile picture URL, show it
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: profilePictureSize,
        height: profilePictureSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceVariant,
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            width: profilePictureSize,
            height: profilePictureSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to icon if image fails to load
              return Icon(
                Icons.person,
                size: profilePictureSize * 0.6,
                color: AppColors.textSecondary,
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              // Show loading indicator while image loads
              return Center(
                child: SizedBox(
                  width: profilePictureSize * 0.4,
                  height: profilePictureSize * 0.4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    
    // Fallback to default icon
    return Container(
      width: profilePictureSize,
      height: profilePictureSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(
          color: AppColors.borderDefault,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.person,
        size: profilePictureSize * 0.6, // Icon is 60% of container size
        color: AppColors.textSecondary,
      ),
    );
  }
}
