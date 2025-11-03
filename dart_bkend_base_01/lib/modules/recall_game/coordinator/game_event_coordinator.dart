import 'dart:async';
import 'dart:math';
import '../../recall_game/shared_logic/recall_game_round.dart';
import '../services/game_registry.dart';
import '../services/game_state_store.dart';
import '../../../server/room_manager.dart';
import '../../../server/websocket_server.dart';
import '../../../utils/server_logger.dart';
import '../shared_logic/utils/deck_factory.dart';
import '../shared_logic/models/card.dart';

const bool LOGGING_SWITCH = true;

/// Coordinates WS game events to the RecallGameRound logic per room.
class GameEventCoordinator {
  final RoomManager roomManager;
  final WebSocketServer server;
  final _registry = GameRegistry.instance;
  final _store = GameStateStore.instance;
  final Logger _logger = Logger();

  GameEventCoordinator(this.roomManager, this.server);

  /// Handle a unified game event from a session
  Future<void> handle(String sessionId, String event, Map<String, dynamic> data) async {
    final roomId = roomManager.getRoomForSession(sessionId);
    if (roomId == null) {
      server.sendToSession(sessionId, {
        'event': 'error',
        'message': 'Not in a room',
      });
      return;
    }

    // Get or create the game round for this room
    final round = _registry.getOrCreate(roomId, server);

    try {
      switch (event) {
        case 'start_match':
          await _handleStartMatch(roomId, round, data);
          break;
        case 'completed_initial_peek':
          await _handleCompletedInitialPeek(roomId, round, sessionId, data);
          break;
        case 'draw_card':
          await round.handleDrawCard((data['source'] as String?) ?? 'deck');
          break;
        case 'play_card':
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (cardId != null && cardId.isNotEmpty) {
            await round.handlePlayCard(cardId);
          }
          break;
        case 'same_rank_play':
          final playerId = (data['player_id'] as String?) ?? (data['playerId'] as String?);
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (playerId != null && cardId != null && cardId.isNotEmpty) {
            await round.handleSameRankPlay(playerId, cardId);
          }
          break;
        case 'queen_peek':
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          final ownerId = data['ownerId'] as String?;
          
          if (cardId != null && cardId.isNotEmpty && ownerId != null && ownerId.isNotEmpty) {
            // Get the peeking player ID from event data (user_id) - this is the actual player making the action
            // During special card window, currentPlayer may be a CPU, but user_id is always the human player
            final peekingPlayerId = (data['user_id'] as String?) ?? 
                                   (data['player_id'] as String?) ?? 
                                   (data['playerId'] as String?);
            
            if (peekingPlayerId != null && peekingPlayerId.isNotEmpty) {
              await round.handleQueenPeek(
                peekingPlayerId: peekingPlayerId,
                targetCardId: cardId,
                targetPlayerId: ownerId,
              );
            }
          }
          break;
        case 'jack_swap':
          final firstCardId = (data['first_card_id'] as String?) ?? (data['firstCardId'] as String?);
          final firstPlayerId = (data['first_player_id'] as String?) ?? (data['firstPlayerId'] as String?);
          final secondCardId = (data['second_card_id'] as String?) ?? (data['secondCardId'] as String?);
          final secondPlayerId = (data['second_player_id'] as String?) ?? (data['secondPlayerId'] as String?);
          
          if (firstCardId != null && firstCardId.isNotEmpty &&
              firstPlayerId != null && firstPlayerId.isNotEmpty &&
              secondCardId != null && secondCardId.isNotEmpty &&
              secondPlayerId != null && secondPlayerId.isNotEmpty) {
            await round.handleJackSwap(
              firstCardId: firstCardId,
              firstPlayerId: firstPlayerId,
              secondCardId: secondCardId,
              secondPlayerId: secondPlayerId,
            );
          }
          break;
        default:
          // Acknowledge unknown-but-allowed for forward-compat
          break;
      }

      // Acknowledge success
      server.sendToSession(sessionId, {
        'event': '${event}_acknowledged',
        'room_id': roomId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _logger.error('GameEventCoordinator: error on $event -> $e', isOn: LOGGING_SWITCH);
      server.sendToSession(sessionId, {
        'event': '${event}_error',
        'room_id': roomId,
        'message': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Initialize match: create base state, players (human/computers), deck, then initialize round
  Future<void> _handleStartMatch(String roomId, RecallGameRound round, Map<String, dynamic> data) async {
    // Prepare initial state compatible with RecallGameRound
    final stateRoot = _store.getState(roomId);
    final current = Map<String, dynamic>.from(stateRoot['game_state'] as Map<String, dynamic>? ?? {});

    // Start from existing players (creator and any joiners already added via hooks)
    final players = List<Map<String, dynamic>>.from(
      (current['players'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );

    // Determine target player count (mimic Python: at least minPlayers)
    // Fallbacks if room metadata missing
    final roomInfo = roomManager.getRoomInfo(roomId);
    final minPlayers = roomInfo?.minPlayers ?? (data['min_players'] as int? ?? 2);
    final maxPlayers = roomInfo?.maxSize ?? (data['max_players'] as int? ?? 4);

    // Auto-create computer players until minPlayers is reached (cap at maxPlayers)
    int needed = minPlayers - players.length;
    if (needed < 0) needed = 0;
    int cpuIndexBase = 1;
    // Find next CPU index not used
    final existingNames = players.map((p) => (p['name'] ?? '').toString()).toSet();
    while (needed > 0 && players.length < maxPlayers) {
      String name;
      do {
        name = 'CPU ${cpuIndexBase++}';
      } while (existingNames.contains(name));
      final cpuId = 'cpu_${DateTime.now().microsecondsSinceEpoch}_$cpuIndexBase';
      players.add({
        'id': cpuId,
        'name': name,
        'isHuman': false,
        'status': 'waiting',
        'hand': <Map<String, dynamic>>[],
        'visible_cards': <Map<String, dynamic>>[],
        'points': 0,
        'known_cards': <String, dynamic>{},
        'collection_rank_cards': <String>[],
        'isActive': true,  // Required for same rank play filtering
        'difficulty': 'medium',  // Default difficulty for computer players
      });
      needed--;
    }

    // Build deck and deal 4 cards per player (as in practice)
    final deckFactory = getDeckFactory(roomId) as dynamic; // returns DeckFactory or TestingDeckFactory
    final List<Card> fullDeck = deckFactory.buildDeck();

    // Helper to convert Card to Map (full data for originalDeck lookup)
    Map<String, dynamic> _cardToMap(Card c) => {
      'cardId': c.cardId,
      'rank': c.rank,
      'suit': c.suit,
      'points': c.points,
      if (c.specialPower != null) 'specialPower': c.specialPower,
    };

    // Helper to create ID-only card (for hands - shows card back)
    // Matches recall game format: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
    Map<String, dynamic> _cardToIdOnly(Card c) => {
      'cardId': c.cardId,
      'suit': '?',      // Face-down: hide suit
      'rank': '?',      // Face-down: hide rank
      'points': 0,      // Face-down: hide points
    };

    // Deal 4 to each player in order
    final originalDeckMaps = fullDeck.map(_cardToMap).toList(); // Full data for lookup
    final drawStack = List<Card>.from(fullDeck);
    for (final p in players) {
      final hand = <Map<String, dynamic>>[];
      for (int i = 0; i < 4 && drawStack.isNotEmpty; i++) {
        final c = drawStack.removeAt(0);
        hand.add(_cardToIdOnly(c)); // ID-only for hands (card backs)
      }
      p['hand'] = hand;
    }

    // Set up discard pile with first card (full data - face-up)
    // Matches recall game: discard pile starts with first card from remaining deck
    final discardPile = <Map<String, dynamic>>[];
    if (drawStack.isNotEmpty) {
      final firstCard = drawStack.removeAt(0);
      discardPile.add(_cardToMap(firstCard)); // Full data for discard pile (face-up)
      _logger.info('GameEventCoordinator: Moved first card ${firstCard.cardId} to discard pile', isOn: LOGGING_SWITCH);
    }

    // Remaining draw pile as ID-only card maps (matches recall game format)
    final drawPileIds = drawStack.map((c) => _cardToIdOnly(c)).toList();

    // Build updated game_state - set to initial_peek phase
    final gameState = <String, dynamic>{
      'gameId': roomId,
      'gameName': 'Recall Game $roomId',
      'players': players,
      'discardPile': discardPile, // Full data (face-up)
      'drawPile': drawPileIds,    // ID-only (face-down)
      'originalDeck': originalDeckMaps,
      'gameType': 'multiplayer',
      'isGameActive': true,
      'phase': 'initial_peek', // Set to initial_peek phase
      'playerCount': players.length,
      'maxPlayers': maxPlayers,
      'minPlayers': minPlayers,
    };

    // Set all players to initial_peek status
    for (final player in players) {
      player['status'] = 'initial_peek';
      // Initialize collection_rank_cards as empty list (not string)
      player['collection_rank_cards'] = <Map<String, dynamic>>[];
      // Initialize known_cards as empty map
      if (player['known_cards'] is! Map<String, dynamic>) {
        player['known_cards'] = <String, dynamic>{};
      }
    }

    stateRoot['game_state'] = gameState;
    _store.mergeRoot(roomId, stateRoot);

    // Process AI initial peeks (select 2 cards, decide collection rank)
    _processAIInitialPeeks(roomId, gameState);

    // Broadcast initial_peek phase snapshot (with AI peek results)
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': gameState,
      'owner_id': server.getRoomOwner(roomId),
      'timestamp': DateTime.now().toIso8601String(),
    });

    // DO NOT call initializeRound() yet - wait for human completed_initial_peek
    _logger.info('GameEventCoordinator: Initial peek phase started - waiting for human player', isOn: LOGGING_SWITCH);
  }

  /// Process AI initial peeks - select 2 random cards and store in known_cards, decide collection rank
  void _processAIInitialPeeks(String roomId, Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<dynamic>? ?? [];
      final random = Random();

      for (final player in players) {
        if (player is! Map<String, dynamic>) continue;
        if (player['isHuman'] == true) continue; // Skip human players

        _selectAndStoreAIPeekCards(player, gameState, random);
      }

      // Update store with modified game state
      _store.setGameState(roomId, gameState);
      _logger.info('GameEventCoordinator: Processed AI initial peeks for all computer players', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to process AI initial peeks: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Select and store AI peek cards for a computer player
  void _selectAndStoreAIPeekCards(Map<String, dynamic> computerPlayer, Map<String, dynamic> gameState, Random random) {
    final hand = computerPlayer['hand'] as List<dynamic>? ?? [];
    if (hand.length < 2) {
      _logger.warning('GameEventCoordinator: Computer player ${computerPlayer['name']} has less than 2 cards, skipping peek', isOn: LOGGING_SWITCH);
      return;
    }

    // Select 2 random cards
    final indices = <int>[];
    while (indices.length < 2) {
      final idx = random.nextInt(hand.length);
      if (!indices.contains(idx)) indices.add(idx);
    }

    final playerId = computerPlayer['id'] as String;

    // Get full card data for both cards from originalDeck
    final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
    final card1IdOnly = hand[indices[0]] as Map<String, dynamic>;
    final card2IdOnly = hand[indices[1]] as Map<String, dynamic>;

    final card1Id = card1IdOnly['cardId'] as String;
    final card2Id = card2IdOnly['cardId'] as String;

    Map<String, dynamic>? card1;
    Map<String, dynamic>? card2;
    for (final card in originalDeck) {
      if (card is Map<String, dynamic> && card['cardId'] == card1Id) {
        card1 = card;
      }
      if (card is Map<String, dynamic> && card['cardId'] == card2Id) {
        card2 = card;
      }
    }

    if (card1 == null || card2 == null) {
      _logger.error('GameEventCoordinator: Failed to get full card data for peeked cards', isOn: LOGGING_SWITCH);
      return;
    }

    // Decide collection rank card using priority logic
    final selectedCardForCollection = _selectCardForCollection(card1, card2, random);

    // Determine which card is NOT the collection card
    final nonCollectionCard = selectedCardForCollection['cardId'] == card1['cardId'] ? card2 : card1;

    // Store only the non-collection card in known_cards with card-ID-based structure
    final knownCards = computerPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    if (knownCards[playerId] == null) {
      knownCards[playerId] = <String, dynamic>{};
    }
    final cardId = nonCollectionCard['cardId'] as String;
    (knownCards[playerId] as Map<String, dynamic>)[cardId] = nonCollectionCard;
    computerPlayer['known_cards'] = knownCards;

    // Add the selected card full data to player's collection_rank_cards list
    final collectionRankCards = computerPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
    collectionRankCards.add(selectedCardForCollection);
    computerPlayer['collection_rank_cards'] = collectionRankCards;
    computerPlayer['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';

    _logger.info('GameEventCoordinator: AI ${computerPlayer['name']} peeked at cards at positions $indices', isOn: LOGGING_SWITCH);
    _logger.info('GameEventCoordinator: AI ${computerPlayer['name']} selected ${selectedCardForCollection['rank']} of ${selectedCardForCollection['suit']} for collection (${selectedCardForCollection['points']} points)', isOn: LOGGING_SWITCH);
  }

  /// AI Decision Logic: Select which card should be marked as collection rank
  /// Priority: Least points first, then by rank order (ace, number, king, queen, jack)
  /// Jokers are excluded from collection rank selection
  Map<String, dynamic> _selectCardForCollection(Map<String, dynamic> card1, Map<String, dynamic> card2, Random random) {
    final rank1 = card1['rank'] as String? ?? '';
    final rank2 = card2['rank'] as String? ?? '';
    final isJoker1 = rank1.toLowerCase() == 'joker';
    final isJoker2 = rank2.toLowerCase() == 'joker';
    
    // Exclude jokers from collection rank selection
    // If one card is a joker and the other is not, select the non-joker
    if (isJoker1 && !isJoker2) {
      return card2;
    }
    if (isJoker2 && !isJoker1) {
      return card1;
    }
    // If both are jokers, pick randomly (shouldn't happen in normal gameplay)
    if (isJoker1 && isJoker2) {
      return random.nextBool() ? card1 : card2;
    }
    
    final points1 = card1['points'] as int? ?? 0;
    final points2 = card2['points'] as int? ?? 0;

    // If points are different, select the one with least points
    if (points1 != points2) {
      return points1 < points2 ? card1 : card2;
    }

    // If points are the same, use priority order: ace, number, king, queen, jack
    final priority1 = _getCardPriority(rank1);
    final priority2 = _getCardPriority(rank2);

    if (priority1 != priority2) {
      return priority1 < priority2 ? card1 : card2;
    }

    // If both cards have same rank, random pick
    return random.nextBool() ? card1 : card2;
  }

  /// Get priority value for card rank (lower = higher priority)
  int _getCardPriority(String rank) {
    switch (rank) {
      case 'ace':
        return 1; // Highest priority
      case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9': case '10':
        return 2; // Numbers
      case 'king':
        return 3; // Kings
      case 'queen':
        return 4; // Queens
      case 'jack':
        return 5; // Jacks (lowest priority)
      default:
        return 6; // Unknown ranks (lowest)
    }
  }

  /// Get full card data by cardId from originalDeck
  Map<String, dynamic>? _getCardById(Map<String, dynamic> gameState, String cardId) {
    final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
    for (final card in originalDeck) {
      if (card is Map<String, dynamic> && card['cardId'] == cardId) {
        return card;
      }
    }
    return null;
  }

  /// Handle the completed_initial_peek event from frontend
  Future<void> _handleCompletedInitialPeek(String roomId, RecallGameRound round, String sessionId, Map<String, dynamic> data) async {
    try {
      _logger.info('GameEventCoordinator: Handling completed initial peek with data: $data', isOn: LOGGING_SWITCH);

      // Extract card_ids from payload
      final cardIds = (data['card_ids'] as List<dynamic>?)?.cast<String>() ?? [];

      if (cardIds.length != 2) {
        _logger.error('GameEventCoordinator: Invalid card_ids: $cardIds. Expected exactly 2 card IDs.', isOn: LOGGING_SWITCH);
        server.sendToSession(sessionId, {
          'event': 'completed_initial_peek_error',
          'room_id': roomId,
          'message': 'Invalid card_ids: Expected exactly 2 card IDs',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      // Get current game state
      final gameState = _store.getGameState(roomId);
      final players = gameState['players'] as List<dynamic>? ?? [];

      // Find human player
      Map<String, dynamic>? humanPlayer;
      for (final player in players) {
        if (player is Map<String, dynamic> && player['isHuman'] == true) {
          humanPlayer = player;
          break;
        }
      }

      if (humanPlayer == null) {
        _logger.error('GameEventCoordinator: Human player not found for completed_initial_peek', isOn: LOGGING_SWITCH);
        server.sendToSession(sessionId, {
          'event': 'completed_initial_peek_error',
          'room_id': roomId,
          'message': 'Human player not found',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      _logger.info('GameEventCoordinator: Human player ${humanPlayer['name']} peeked at cards: $cardIds', isOn: LOGGING_SWITCH);

      // Clear any existing cards from previous peeks
      humanPlayer['cardsToPeek'] = <Map<String, dynamic>>[];

      // Get full card data for both card_ids from originalDeck
      final cardsToPeek = <Map<String, dynamic>>[];
      for (final cardId in cardIds) {
        final cardData = _getCardById(gameState, cardId);
        if (cardData == null) {
          _logger.error('GameEventCoordinator: Card $cardId not found in game', isOn: LOGGING_SWITCH);
          continue;
        }
        cardsToPeek.add(cardData);
      }

      if (cardsToPeek.length != 2) {
        _logger.error('GameEventCoordinator: Only found ${cardsToPeek.length} out of 2 cards', isOn: LOGGING_SWITCH);
        server.sendToSession(sessionId, {
          'event': 'completed_initial_peek_error',
          'room_id': roomId,
          'message': 'Failed to find card data',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      // Update player's cardsToPeek with full card data
      humanPlayer['cardsToPeek'] = cardsToPeek;

      // Store peeked cards in known_cards with card-ID-based structure
      final humanKnownCards = humanPlayer['known_cards'] as Map<String, dynamic>? ?? {};
      final playerId = humanPlayer['id'] as String;
      if (humanKnownCards[playerId] == null) {
        humanKnownCards[playerId] = <String, dynamic>{};
      }
      for (final card in cardsToPeek) {
        if (card['cardId'] != null) {
          final cardId = card['cardId'] as String;
          (humanKnownCards[playerId] as Map<String, dynamic>)[cardId] = card;
        }
      }
      humanPlayer['known_cards'] = humanKnownCards;

      // Auto-select collection rank card for human player (same logic as AI)
      final selectedCardForCollection = _selectCardForCollection(cardsToPeek[0], cardsToPeek[1], Random());

      final fullCardData = _getCardById(gameState, selectedCardForCollection['cardId'] as String);
      if (fullCardData != null) {
        final collectionRankCards = humanPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
        collectionRankCards.add(fullCardData);
        humanPlayer['collection_rank_cards'] = collectionRankCards;
        humanPlayer['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';

        _logger.info('GameEventCoordinator: Human player selected ${selectedCardForCollection['rank']} of ${selectedCardForCollection['suit']} for collection (${selectedCardForCollection['points']} points)', isOn: LOGGING_SWITCH);
      } else {
        _logger.error('GameEventCoordinator: Failed to get full card data for human collection rank card', isOn: LOGGING_SWITCH);
      }

      // Set human player status to WAITING
      humanPlayer['status'] = 'waiting';

      // Update game state
      _store.setGameState(roomId, gameState);

      // Broadcast update
      server.broadcastToRoom(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'owner_id': server.getRoomOwner(roomId),
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('GameEventCoordinator: Completed initial peek - human player set to WAITING status', isOn: LOGGING_SWITCH);

      // Wait 5 seconds then trigger completeInitialPeek to clear states and initialize round
      Timer(Duration(seconds: 5), () {
        _logger.info('GameEventCoordinator: 5-second delay completed, triggering completeInitialPeek', isOn: LOGGING_SWITCH);
        _completeInitialPeek(roomId, round);
      });

    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to handle completed initial peek: $e', isOn: LOGGING_SWITCH);
      server.sendToSession(sessionId, {
        'event': 'completed_initial_peek_error',
        'room_id': roomId,
        'message': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Complete initial peek phase: clear cardsToPeek, set all status='waiting', phase='player_turn', then initialize round
  void _completeInitialPeek(String roomId, RecallGameRound round) {
    try {
      final gameState = _store.getGameState(roomId);
      final players = gameState['players'] as List<dynamic>? ?? [];

      // Clear cardsToPeek for all players
      for (final player in players) {
        if (player is Map<String, dynamic>) {
          player['cardsToPeek'] = <Map<String, dynamic>>[];
          player['status'] = 'waiting';
        }
      }

      // Set phase to player_turn
      gameState['phase'] = 'player_turn';

      // Update store
      _store.setGameState(roomId, gameState);

      // Broadcast phase transition
      server.broadcastToRoom(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'owner_id': server.getRoomOwner(roomId),
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('GameEventCoordinator: Initial peek phase completed - transitioning to player_turn', isOn: LOGGING_SWITCH);

      // NOW initialize the round (starts actual gameplay)
      round.initializeRound();
    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to complete initial peek: $e', isOn: LOGGING_SWITCH);
    }
  }
}


