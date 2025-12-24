import '../../utils/platform/shared_imports.dart';
import '../../../cleco_game/backend_core/shared_logic/cleco_game_round.dart';
import '../services/game_registry.dart';
import '../services/game_state_store.dart';
import '../shared_logic/utils/deck_factory.dart';
import '../shared_logic/models/card.dart';
import '../../utils/platform/predefined_hands_loader.dart';

const bool LOGGING_SWITCH = false; // Enabled for comp player testing

/// Coordinates WS game events to the ClecoGameRound logic per room.
class GameEventCoordinator {
  final RoomManager roomManager;
  final WebSocketServer server;
  final _registry = GameRegistry.instance;
  final _store = GameStateStore.instance;
  final Logger _logger = Logger();
  final Map<String, Timer?> _initialPeekTimers = {};

  GameEventCoordinator(this.roomManager, this.server);

  /// Get current games map in Flutter format: {roomId: {'gameData': {'game_state': ...}}}
  /// This matches the format expected by shared logic methods
  Map<String, dynamic> _getCurrentGamesMap(String roomId) {
    try {
      final state = _store.getState(roomId);
      final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
      
      return {
        roomId: {
          'gameData': {
            'game_id': roomId,
            'game_state': gameState,
            'owner_id': server.getRoomOwner(roomId),
          },
        },
      };
    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to get current games map: $e', isOn: LOGGING_SWITCH);
      return {};
    }
  }

  /// Get player ID from session ID and room ID
  /// Returns the player ID associated with the session
  /// Since player IDs are now sessionIds, this simply returns the sessionId
  /// after verifying the player exists in the game
  String? _getPlayerIdFromSession(String sessionId, String roomId) {
    try {
      // Player ID is now sessionId - verify player exists in game
      final gameState = _store.getGameState(roomId);
      final players = (gameState['players'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      // Check if a player with this sessionId exists
      final playerExists = players.any((p) => p['id'] == sessionId);
      if (playerExists) {
        return sessionId; // Player ID = sessionId
      }

      _logger.warning('GameEventCoordinator: No player found with sessionId $sessionId in room $roomId', isOn: LOGGING_SWITCH);
      return null;
    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to get player ID from session: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }

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
          final gamesMap = _getCurrentGamesMap(roomId);
          final playerId = _getPlayerIdFromSession(sessionId, roomId);
          await round.handleDrawCard(
            (data['source'] as String?) ?? 'deck',
            playerId: playerId,
            gamesMap: gamesMap,
          );
          break;
        case 'play_card':
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (cardId != null && cardId.isNotEmpty) {
            final gamesMap = _getCurrentGamesMap(roomId);
            final playerId = _getPlayerIdFromSession(sessionId, roomId);
            await round.handlePlayCard(
              cardId,
              playerId: playerId,
              gamesMap: gamesMap,
            );
          }
          break;
        case 'same_rank_play':
          // Use sessionId as player ID (player_id from event should be sessionId)
          final playerId = _getPlayerIdFromSession(sessionId, roomId) ?? 
                          (data['player_id'] as String?) ?? 
                          (data['playerId'] as String?);
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (playerId != null && cardId != null && cardId.isNotEmpty) {
            final gamesMap = _getCurrentGamesMap(roomId);
            await round.handleSameRankPlay(playerId, cardId, gamesMap: gamesMap);
          }
          break;
        case 'queen_peek':
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          final ownerId = data['ownerId'] as String?;
          
          if (cardId != null && cardId.isNotEmpty && ownerId != null && ownerId.isNotEmpty) {
            // Use sessionId as peeking player ID (player_id from event should be sessionId)
            // Player ID is now sessionId, so use sessionId directly
            final peekingPlayerId = _getPlayerIdFromSession(sessionId, roomId) ??
                                   (data['player_id'] as String?) ?? 
                                   (data['playerId'] as String?);
            
            if (peekingPlayerId != null && peekingPlayerId.isNotEmpty) {
              final gamesMap = _getCurrentGamesMap(roomId);
              await round.handleQueenPeek(
                peekingPlayerId: peekingPlayerId,
                targetCardId: cardId,
                targetPlayerId: ownerId,
                gamesMap: gamesMap,
              );
            }
          }
          break;
        case 'jack_swap':
          _logger.info('🃏 GameEventCoordinator: jack_swap case reached', isOn: LOGGING_SWITCH);
          final firstCardId = (data['first_card_id'] as String?) ?? (data['firstCardId'] as String?);
          final firstPlayerId = (data['first_player_id'] as String?) ?? (data['firstPlayerId'] as String?);
          final secondCardId = (data['second_card_id'] as String?) ?? (data['secondCardId'] as String?);
          final secondPlayerId = (data['second_player_id'] as String?) ?? (data['secondPlayerId'] as String?);
          
          _logger.info('🃏 GameEventCoordinator: jack_swap event received - firstCardId: $firstCardId, firstPlayerId: $firstPlayerId, secondCardId: $secondCardId, secondPlayerId: $secondPlayerId', isOn: LOGGING_SWITCH);
          
          if (firstCardId != null && firstCardId.isNotEmpty &&
              firstPlayerId != null && firstPlayerId.isNotEmpty &&
              secondCardId != null && secondCardId.isNotEmpty &&
              secondPlayerId != null && secondPlayerId.isNotEmpty) {
            final gamesMap = _getCurrentGamesMap(roomId);
            await round.handleJackSwap(
              firstCardId: firstCardId,
              firstPlayerId: firstPlayerId,
              secondCardId: secondCardId,
              secondPlayerId: secondPlayerId,
              gamesMap: gamesMap,
            );
          } else {
            _logger.error('GameEventCoordinator: jack_swap validation failed - missing required fields. firstCardId: $firstCardId, firstPlayerId: $firstPlayerId, secondCardId: $secondCardId, secondPlayerId: $secondPlayerId', isOn: LOGGING_SWITCH);
            server.sendToSession(sessionId, {
              'event': 'jack_swap_error',
              'room_id': roomId,
              'message': 'Missing required fields for jack swap',
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
          break;
        case 'collect_from_discard':
          final gamesMap = _getCurrentGamesMap(roomId);
          final playerId = _getPlayerIdFromSession(sessionId, roomId);
          if (playerId != null && playerId.isNotEmpty) {
            await round.handleCollectFromDiscard(
              playerId,
              gamesMap: gamesMap,
            );
          }
          break;
        case 'call_final_round':
        case 'call_cleco': // Keep for backward compatibility
          final gamesMap = _getCurrentGamesMap(roomId);
          final playerId = _getPlayerIdFromSession(sessionId, roomId);
          if (playerId != null && playerId.isNotEmpty) {
            await round.handleCallFinalRound(
              playerId,
              gamesMap: gamesMap,
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
  Future<void> _handleStartMatch(String roomId, ClecoGameRound round, Map<String, dynamic> data) async {
    // Prepare initial state compatible with ClecoGameRound
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

    // Auto-create computer players
    // For practice mode: fill to maxPlayers (practice rooms start with "practice_room_")
    // For random join rooms: fill to maxPlayers (indicated by is_random_join flag)
    // For autoStart rooms: fill to maxPlayers (rooms with autoStart=true)
    // For regular multiplayer: only fill to minPlayers (wait for real players to join)
    final isPracticeMode = roomId.startsWith('practice_room_');
    final isRandomJoin = data['is_random_join'] == true;
    final isAutoStart = roomInfo?.autoStart == true;
    int needed = (isPracticeMode || isRandomJoin || isAutoStart)
        ? maxPlayers - players.length  // Practice mode, random join, or autoStart: fill to maxPlayers
        : minPlayers - players.length; // Regular multiplayer: only fill to minPlayers
    if (needed < 0) needed = 0;
    
    _logger.info('GameEventCoordinator: CPU player creation - isPracticeMode: $isPracticeMode, isRandomJoin: $isRandomJoin, isAutoStart: $isAutoStart, currentPlayers: ${players.length}, needed: $needed, target: ${(isPracticeMode || isRandomJoin || isAutoStart) ? maxPlayers : minPlayers}', isOn: LOGGING_SWITCH);
    
    // Get existing player names to avoid duplicates
    final existingNames = players.map((p) => (p['name'] ?? '').toString()).toSet();
    int cpuIndexBase = 1;
    
    // Skip comp player fetching for practice mode - use simulated CPU players
    if (isPracticeMode) {
      _logger.info('GameEventCoordinator: Practice mode detected - using simulated CPU players', isOn: LOGGING_SWITCH);
      // Create simulated CPU players (existing logic)
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
        existingNames.add(name);  // Track name to avoid duplicates
        needed--;
      }
    } else {
      // Multiplayer mode: Try to fetch comp players from Flask backend
      _logger.info('GameEventCoordinator: Multiplayer mode - fetching comp players from Flask backend', isOn: LOGGING_SWITCH);
      
      int compPlayersAdded = 0;
      int remainingNeeded = needed;
      
      try {
        // Fetch comp players from Flask backend
        final compPlayersResponse = await server.pythonClient.getCompPlayers(needed);
        final success = compPlayersResponse['success'] as bool? ?? false;
        final compPlayersList = compPlayersResponse['comp_players'] as List<dynamic>? ?? [];
        final returnedCount = compPlayersResponse['count'] as int? ?? 0;
        
        if (success && compPlayersList.isNotEmpty) {
          _logger.info('GameEventCoordinator: Retrieved $returnedCount comp player(s) from Flask backend', isOn: LOGGING_SWITCH);
          
          // Add comp players to players list
          for (final compPlayerData in compPlayersList) {
            if (compPlayerData is! Map<String, dynamic>) continue;
            if (players.length >= maxPlayers) break;
            
            final userId = compPlayerData['user_id'] as String? ?? '';
            final username = compPlayerData['username'] as String? ?? 'CompPlayer';
            final email = compPlayerData['email'] as String? ?? '';
            
            // Generate a unique player ID (use userId as base, but ensure uniqueness)
            // For comp players, we can use userId directly or create a sessionId-like ID
            final playerId = 'comp_${userId}_${DateTime.now().microsecondsSinceEpoch}';
            
            // Ensure username is unique
            String uniqueName = username;
            int nameSuffix = 1;
            while (existingNames.contains(uniqueName)) {
              uniqueName = '$username$nameSuffix';
              nameSuffix++;
            }
            existingNames.add(uniqueName);
            
            players.add({
              'id': playerId,
              'name': uniqueName,
              'isHuman': false,
              'status': 'waiting',
              'hand': <Map<String, dynamic>>[],
              'visible_cards': <Map<String, dynamic>>[],
              'points': 0,
              'known_cards': <String, dynamic>{},
              'collection_rank_cards': <String>[],
              'isActive': true,  // Required for same rank play filtering
              'difficulty': 'medium',  // Default difficulty for computer players
              'userId': userId,  // Store userId for coin deduction logic
              'email': email,  // Store email for reference
            });
            
            compPlayersAdded++;
            remainingNeeded--;
            
            _logger.info('GameEventCoordinator: Added comp player - id: $playerId, name: $uniqueName, userId: $userId', isOn: LOGGING_SWITCH);
          }
          
          _logger.info('GameEventCoordinator: Added $compPlayersAdded comp player(s) from database', isOn: LOGGING_SWITCH);
        } else {
          _logger.warning('GameEventCoordinator: No comp players returned from Flask backend (success: $success, count: $returnedCount)', isOn: LOGGING_SWITCH);
        }
      } catch (e) {
        _logger.error('GameEventCoordinator: Error fetching comp players from Flask backend: $e', isOn: LOGGING_SWITCH);
        // Continue to fallback logic below
      }
      
      // Fallback: Create simulated CPU players for any remaining slots
      if (remainingNeeded > 0) {
        _logger.info('GameEventCoordinator: Creating $remainingNeeded simulated CPU player(s) as fallback', isOn: LOGGING_SWITCH);
        
        while (remainingNeeded > 0 && players.length < maxPlayers) {
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
          existingNames.add(name);
          remainingNeeded--;
        }
        
        _logger.info('GameEventCoordinator: Created ${needed - remainingNeeded} simulated CPU player(s) as fallback', isOn: LOGGING_SWITCH);
      }
    }

    // Build deck and deal 4 cards per player (as in practice)
    // Use YamlDeckFactory to respect testing_mode setting from YAML config
    final deckFactory = await YamlDeckFactory.fromFile(roomId, DECK_CONFIG_PATH);
    final List<Card> fullDeck = deckFactory.buildDeck();
    
    _logger.info('GameEventCoordinator: Built deck with ${fullDeck.length} cards (testing_mode: ${deckFactory.getSummary()['testing_mode']})', isOn: LOGGING_SWITCH);

    // Helper to convert Card to Map (full data for originalDeck lookup)
    Map<String, dynamic> _cardToMap(Card c) => {
      'cardId': c.cardId,
      'rank': c.rank,
      'suit': c.suit,
      'points': c.points,
      if (c.specialPower != null) 'specialPower': c.specialPower,
    };

    // Helper to create ID-only card (for hands - shows card back)
    // Matches cleco game format: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
    Map<String, dynamic> _cardToIdOnly(Card c) => {
      'cardId': c.cardId,
      'suit': '?',      // Face-down: hide suit
      'rank': '?',      // Face-down: hide rank
      'points': 0,      // Face-down: hide points
    };

    // Load predefined hands configuration if available
    final predefinedHandsLoader = PredefinedHandsLoader();
    final predefinedHandsConfig = await predefinedHandsLoader.loadConfig();
    final usePredefinedHands = predefinedHandsConfig['enabled'] == true;
    
    if (usePredefinedHands) {
      _logger.info('GameEventCoordinator: Predefined hands enabled - using predefined hands for dealing', isOn: LOGGING_SWITCH);
    } else {
      _logger.info('GameEventCoordinator: Predefined hands disabled - using random dealing', isOn: LOGGING_SWITCH);
    }

    // Deal 4 to each player in order
    final originalDeckMaps = fullDeck.map(_cardToMap).toList(); // Full data for lookup
    final drawStack = List<Card>.from(fullDeck);
    
    for (int playerIndex = 0; playerIndex < players.length; playerIndex++) {
      final p = players[playerIndex];
      final hand = <Map<String, dynamic>>[];
      
      // Check if predefined hand exists for this player
      if (usePredefinedHands) {
        final predefinedHand = predefinedHandsLoader.getHandForPlayer(predefinedHandsConfig, playerIndex);
        
        if (predefinedHand != null && predefinedHand.length == 4) {
          _logger.info('GameEventCoordinator: Using predefined hand for player $playerIndex: $predefinedHand', isOn: LOGGING_SWITCH);
          
          // Find and deal the predefined cards from the deck
          for (final cardSpec in predefinedHand) {
            final rank = cardSpec['rank']?.toString();
            final suit = cardSpec['suit']?.toString();
            
            if (rank == null || suit == null) {
              _logger.warning('GameEventCoordinator: Invalid card spec in predefined hand: $cardSpec', isOn: LOGGING_SWITCH);
              continue;
            }
            
            // Find the card in the draw stack
            int cardIndex = -1;
            for (int i = 0; i < drawStack.length; i++) {
              if (drawStack[i].rank == rank && drawStack[i].suit == suit) {
                cardIndex = i;
                break;
              }
            }
            
            if (cardIndex >= 0) {
              final c = drawStack.removeAt(cardIndex);
              hand.add(_cardToIdOnly(c));
              _logger.info('GameEventCoordinator: Dealt predefined card: $rank of $suit (${c.cardId}) to player $playerIndex', isOn: LOGGING_SWITCH);
            } else {
              _logger.warning('GameEventCoordinator: Predefined card not found in deck: $rank of $suit for player $playerIndex', isOn: LOGGING_SWITCH);
              // Fallback: deal a random card if predefined card not found
              if (drawStack.isNotEmpty) {
                final c = drawStack.removeAt(0);
                hand.add(_cardToIdOnly(c));
              }
            }
          }
          
          // Ensure we have exactly 4 cards
          while (hand.length < 4 && drawStack.isNotEmpty) {
            final c = drawStack.removeAt(0);
            hand.add(_cardToIdOnly(c));
            _logger.warning('GameEventCoordinator: Added fallback card to player $playerIndex to complete hand', isOn: LOGGING_SWITCH);
          }
        } else {
          // No predefined hand for this player, deal randomly
          _logger.info('GameEventCoordinator: No predefined hand for player $playerIndex, dealing randomly', isOn: LOGGING_SWITCH);
      for (int i = 0; i < 4 && drawStack.isNotEmpty; i++) {
        final c = drawStack.removeAt(0);
            hand.add(_cardToIdOnly(c));
          }
        }
      } else {
        // Predefined hands disabled, deal randomly
        for (int i = 0; i < 4 && drawStack.isNotEmpty; i++) {
          final c = drawStack.removeAt(0);
          hand.add(_cardToIdOnly(c));
        }
      }
      
      p['hand'] = hand;
    }

    // Set up discard pile with first card (full data - face-up)
    // Matches cleco game: discard pile starts with first card from remaining deck
    final discardPile = <Map<String, dynamic>>[];
    if (drawStack.isNotEmpty) {
      final firstCard = drawStack.removeAt(0);
      discardPile.add(_cardToMap(firstCard)); // Full data for discard pile (face-up)
      _logger.info('GameEventCoordinator: Moved first card ${firstCard.cardId} to discard pile', isOn: LOGGING_SWITCH);
    }

    // Remaining draw pile as ID-only card maps (matches cleco game format)
    final drawPileIds = drawStack.map((c) => _cardToIdOnly(c)).toList();

    // Extract showInstructions from data (practice mode) or default to false
    final showInstructions = data['showInstructions'] as bool? ?? false;
    
    // Get turnTimeLimit from room config (reuse roomInfo from earlier in method)
    final turnTimeLimit = roomInfo?.turnTimeLimit ?? 30;

    // Calculate pot: coin_cost × number_of_active_players (regardless of subscription tier)
    // Default coin cost is 25 (will be tied to match_class in future)
    final coinCost = 25;
    final activePlayerCount = players.length;
    final pot = coinCost * activePlayerCount;
    
    _logger.info('GameEventCoordinator: Calculated pot for game $roomId - coin_cost: $coinCost, players: $activePlayerCount, pot: $pot', isOn: LOGGING_SWITCH);
    
    // Build updated game_state - set to initial_peek phase
    final gameState = <String, dynamic>{
      'gameId': roomId,
      'gameName': 'Cleco Game $roomId',
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
      'showInstructions': showInstructions, // Store instructions switch
      'turnTimeLimit': turnTimeLimit, // Store turn time limit
      'match_class': 'standard', // Placeholder for future match class system
      'coin_cost_per_player': coinCost,
      'match_pot': pot,
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
      // Ensure isActive is set to true for all players (required for winner calculation)
      if (player['isActive'] != true) {
        player['isActive'] = true;
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

    // Start 15-second timer for initial peek phase (only if instructions are not shown)
    if (!showInstructions) {
      _initialPeekTimers[roomId]?.cancel();
      _initialPeekTimers[roomId] = Timer(Duration(seconds: 15), () {
        _onInitialPeekTimerExpired(roomId, round);
      });
      _logger.info('GameEventCoordinator: Initial peek phase started - 15-second timer started', isOn: LOGGING_SWITCH);
    } else {
      _logger.info('GameEventCoordinator: Initial peek phase started - timer disabled (showInstructions=true)', isOn: LOGGING_SWITCH);
    }

    // DO NOT call initializeRound() yet - wait for timer expiry or all players complete
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

    // Add ID-only cardsToPeek for CPU players (for tracking/logic purposes)
    // CPU players get ID-only format since full data is already in known_cards
    computerPlayer['cardsToPeek'] = [
      {'cardId': card1Id, 'suit': '?', 'rank': '?', 'points': 0},
      {'cardId': card2Id, 'suit': '?', 'rank': '?', 'points': 0},
    ];
    _logger.info('GameEventCoordinator: Added ID-only cardsToPeek for CPU player ${computerPlayer['name']}: [$card1Id, $card2Id]', isOn: LOGGING_SWITCH);

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

  /// Check if all players have completed initial peek
  /// A player has completed if they have collection_rank set and collection_rank_cards populated
  bool _allPlayersCompletedInitialPeek(String roomId) {
    final gameState = _store.getGameState(roomId);
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    for (final player in players) {
      if (player is! Map<String, dynamic>) continue;
      
      final collectionRank = player['collection_rank'] as String?;
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      
      // Player hasn't completed if collection_rank is null/empty or collection_rank_cards is empty
      if (collectionRank == null || collectionRank.isEmpty || collectionRankCards.isEmpty) {
        return false;
      }
    }
    
    return true;
  }

  /// Handle the completed_initial_peek event from frontend
  Future<void> _handleCompletedInitialPeek(String roomId, ClecoGameRound round, String sessionId, Map<String, dynamic> data) async {
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

      // Find human player by sessionId (player ID = sessionId)
      Map<String, dynamic>? humanPlayer;
      final playerIdFromSession = _getPlayerIdFromSession(sessionId, roomId);
      if (playerIdFromSession != null) {
        final foundPlayer = players.firstWhere(
          (p) => p is Map<String, dynamic> && p['id'] == playerIdFromSession,
          orElse: () => <String, dynamic>{},
        );
        // Verify it's actually a human player and not empty
        if (foundPlayer.isNotEmpty && foundPlayer['isHuman'] == true) {
          humanPlayer = foundPlayer as Map<String, dynamic>;
        } else if (foundPlayer.isNotEmpty) {
          _logger.warning('GameEventCoordinator: Player $playerIdFromSession found but is not human', isOn: LOGGING_SWITCH);
        }
      }

      if (humanPlayer == null || humanPlayer.isEmpty) {
        _logger.error('GameEventCoordinator: Human player with sessionId $sessionId not found for completed_initial_peek', isOn: LOGGING_SWITCH);
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

      // Get current games map (matching draw card pattern)
      final currentGames = _getCurrentGamesMap(roomId);
      final playerId = humanPlayer['id'] as String;
      
      // Get player from games map structure (matching draw card pattern)
      final gameData = currentGames[roomId]?['gameData']?['game_state'] as Map<String, dynamic>?;
      if (gameData == null) {
        _logger.error('GameEventCoordinator: Failed to get game data from games map', isOn: LOGGING_SWITCH);
        return;
      }
      final playersInGamesMap = gameData['players'] as List<dynamic>? ?? [];
      final playerInGamesMap = playersInGamesMap.firstWhere(
        (p) => p is Map<String, dynamic> && p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>;
      
      if (playerInGamesMap.isEmpty) {
        _logger.error('GameEventCoordinator: Player $playerId not found in games map', isOn: LOGGING_SWITCH);
        return;
      }

      // Create callback instance for this room (matching GameRegistry pattern)
      final callback = ServerGameStateCallbackImpl(roomId, server);

      // STEP 1: Set cardsToPeek to ID-only format in games map and broadcast to all except peeking player
      // This matches the draw card pattern exactly
      final idOnlyCardsToPeek = cardIds.map((cardId) => {
        'cardId': cardId,
        'suit': '?',
        'rank': '?',
        'points': 0,
      }).toList();
      playerInGamesMap['cardsToPeek'] = idOnlyCardsToPeek;
      
      // Use callback method to broadcast (matches draw card pattern)
      callback.broadcastGameStateExcept(playerId, {
        'games': currentGames, // Games map with ID-only cardsToPeek
      });
      _logger.info('GameEventCoordinator: STEP 1 - Broadcast ID-only cardsToPeek to all except player $playerId', isOn: LOGGING_SWITCH);

      // STEP 2: Set cardsToPeek to full card data in games map and send only to peeking player
      // This matches the draw card pattern exactly
      playerInGamesMap['cardsToPeek'] = cardsToPeek;
      
      // Use callback method to send to player (matches draw card pattern)
      callback.sendGameStateToPlayer(playerId, {
        'games': currentGames, // Games map with full cardsToPeek
      });
      _logger.info('GameEventCoordinator: STEP 2 - Sent full cardsToPeek data to player $playerId only', isOn: LOGGING_SWITCH);
      
      // Also update the humanPlayer reference for subsequent logic (known_cards, collection_rank, etc.)
      humanPlayer['cardsToPeek'] = cardsToPeek;

      // Auto-select collection rank card for human player (same logic as AI)
      // IMPORTANT: Must select collection card BEFORE storing in known_cards
      // so we can exclude it from known_cards (just like computer players)
      final selectedCardForCollection = _selectCardForCollection(cardsToPeek[0], cardsToPeek[1], Random());
      
      // Determine which card is NOT the collection card
      final nonCollectionCard = selectedCardForCollection['cardId'] == cardsToPeek[0]['cardId'] 
          ? cardsToPeek[1] 
          : cardsToPeek[0];

      // Store only the non-collection card in known_cards with card-ID-based structure
      // (same logic as computer players - collection cards should NOT be in known_cards)
      final humanKnownCards = humanPlayer['known_cards'] as Map<String, dynamic>? ?? {};
      if (humanKnownCards[playerId] == null) {
        humanKnownCards[playerId] = <String, dynamic>{};
      }
      final nonCollectionCardId = nonCollectionCard['cardId'] as String;
      (humanKnownCards[playerId] as Map<String, dynamic>)[nonCollectionCardId] = nonCollectionCard;
      humanPlayer['known_cards'] = humanKnownCards;
      // Also update in games map for consistency
      playerInGamesMap['known_cards'] = humanKnownCards;

      final fullCardData = _getCardById(gameState, selectedCardForCollection['cardId'] as String);
      if (fullCardData != null) {
        final collectionRankCards = humanPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
        collectionRankCards.add(fullCardData);
        humanPlayer['collection_rank_cards'] = collectionRankCards;
        humanPlayer['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';
        // Also update in games map for consistency
        playerInGamesMap['collection_rank_cards'] = collectionRankCards;
        playerInGamesMap['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';

        _logger.info('GameEventCoordinator: Human player selected ${selectedCardForCollection['rank']} of ${selectedCardForCollection['suit']} for collection (${selectedCardForCollection['points']} points)', isOn: LOGGING_SWITCH);
      } else {
        _logger.error('GameEventCoordinator: Failed to get full card data for human collection rank card', isOn: LOGGING_SWITCH);
      }

      // Set human player status to WAITING
      humanPlayer['status'] = 'waiting';
      // Also update status in games map for consistency
      playerInGamesMap['status'] = 'waiting';

      // Update game state with known_cards, collection_rank, and status changes
      // The callback methods already updated the store for cardsToPeek, but we need to update
      // the store with the known_cards, collection_rank, and status changes
      _store.setGameState(roomId, gameState);

      // Broadcast status update to all players (status change after peek completion)
      final updatedGames = _getCurrentGamesMap(roomId);
      callback.broadcastGameStateExcept(playerId, {
        'games': updatedGames, // Games map with updated status
      });
      // Also send to the player to ensure they have the latest state
      callback.sendGameStateToPlayer(playerId, {
        'games': updatedGames, // Games map with updated status
      });

      _logger.info('GameEventCoordinator: Completed initial peek - human player set to WAITING status', isOn: LOGGING_SWITCH);

      // Check if all players have completed initial peek
      if (_allPlayersCompletedInitialPeek(roomId)) {
        _logger.info('GameEventCoordinator: All players completed initial peek, cancelling timer and completing phase', isOn: LOGGING_SWITCH);
        // Cancel the timer since all players completed
        _initialPeekTimers[roomId]?.cancel();
        _initialPeekTimers[roomId] = null;
        // Complete initial peek phase immediately
        _completeInitialPeek(roomId, round);
      } else {
        _logger.info('GameEventCoordinator: Player completed initial peek, waiting for others or timer expiry', isOn: LOGGING_SWITCH);
      }

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

  /// Auto-complete initial peek for remaining human players
  /// Uses same logic as CPU players (select 2 random cards, decide collection rank)
  void _autoCompleteRemainingHumanPlayers(String roomId, Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<dynamic>? ?? [];
      final random = Random();
      
      for (final player in players) {
        if (player is! Map<String, dynamic>) continue;
        if (player['isHuman'] != true) continue; // Skip CPU players
        
        // Check if player has already completed
        final collectionRank = player['collection_rank'] as String?;
        final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
        
        if (collectionRank != null && collectionRank.isNotEmpty && collectionRankCards.isNotEmpty) {
          continue; // Player already completed
        }
        
        // Player hasn't completed - apply auto logic
        _logger.info('GameEventCoordinator: Auto-completing initial peek for human player ${player['name']}', isOn: LOGGING_SWITCH);
        _selectAndStoreAIPeekCards(player, gameState, random);
        
        // Set status to waiting (same as when human completes manually)
        player['status'] = 'waiting';
      }
      
      // Update store with modified game state
      _store.setGameState(roomId, gameState);
      
      // Broadcast updated state to all players
      server.broadcastToRoom(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'owner_id': server.getRoomOwner(roomId),
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _logger.info('GameEventCoordinator: Auto-completed initial peek for remaining human players', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to auto-complete remaining human players: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle initial peek timer expiration
  void _onInitialPeekTimerExpired(String roomId, ClecoGameRound round) {
    try {
      _logger.info('GameEventCoordinator: Initial peek timer expired for room $roomId', isOn: LOGGING_SWITCH);
      
      // Clear timer reference
      _initialPeekTimers[roomId] = null;
      
      final gameState = _store.getGameState(roomId);
      
      // Check if all players have completed
      if (!_allPlayersCompletedInitialPeek(roomId)) {
        _logger.info('GameEventCoordinator: Not all players completed initial peek, applying auto logic', isOn: LOGGING_SWITCH);
        
        // Apply auto logic to remaining human players
        _autoCompleteRemainingHumanPlayers(roomId, gameState);
      }
      
      // Now complete initial peek phase (all players should be done)
      _completeInitialPeek(roomId, round);
    } catch (e) {
      _logger.error('GameEventCoordinator: Failed to handle initial peek timer expiry: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Complete initial peek phase: clear cardsToPeek, set all status='waiting', phase='player_turn', then initialize round
  void _completeInitialPeek(String roomId, ClecoGameRound round) {
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

  /// Cleanup resources for a room
  void cleanup(String roomId) {
    _initialPeekTimers[roomId]?.cancel();
    _initialPeekTimers.remove(roomId);
  }
}


