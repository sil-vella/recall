import '../../utils/platform/shared_imports.dart';
import '../utils/rank_matcher.dart';
import '../utils/level_matcher.dart';
import '../../../dutch_game/backend_core/shared_logic/dutch_game_round.dart';
import '../services/game_registry.dart';
import '../services/game_state_store.dart';
import '../shared_logic/utils/deck_factory.dart';
import '../shared_logic/models/card.dart';
import '../../utils/platform/predefined_hands_loader.dart';


/// Coordinates WS game events to the DutchGameRound logic per room.
class GameEventCoordinator {
  final RoomManager roomManager;
  final WebSocketServer server;
  final _registry = GameRegistry.instance;
  final _store = GameStateStore.instance;
  final Map<String, Timer?> _initialPeekTimers = {};

  /// Serialize game events per room so async handlers never interleave (race on shared state).
  final Map<String, Future<void>> _roomEventTail = {};

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
      
      return {};
    }
  }

  /// Get player ID from session ID and room ID
  /// Returns the player ID associated with the session
  /// Since player IDs are now sessionIds, this simply returns the sessionId
  /// after verifying the player exists in the game
  String? _getPlayerIdFromSession(String sessionId, String roomId) {
    try {
      final gameState = _store.getGameState(roomId);
      final players = (gameState['players'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final room = roomManager.getRoom(roomId);
      final stableFromBinding = room?.seatIdForSession(sessionId);

      final candidates = <String>{
        if (stableFromBinding != null && stableFromBinding.isNotEmpty) stableFromBinding,
        sessionId,
      };

      for (final cid in candidates) {
        final ok = players.any((p) => p['id'] == cid);
        if (ok) return cid;
      }

      
      return null;
    } catch (e) {
      
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

    final previous = _roomEventTail[roomId] ?? Future.value();
    final done = Completer<void>();
    _roomEventTail[roomId] = done.future;

    await previous;
    try {
      await _dispatchGameEvent(sessionId, roomId, round, event, data);

      // Acknowledge success
      server.sendToSession(sessionId, {
        'event': '${event}_acknowledged',
        'room_id': roomId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e, stackTrace) {
      
      
      server.sendToSession(sessionId, {
        'event': '${event}_error',
        'room_id': roomId,
        'message': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    } finally {
      if (!done.isCompleted) {
        done.complete();
      }
    }
  }

  Future<void> _dispatchGameEvent(
    String sessionId,
    String roomId,
    DutchGameRound round,
    String event,
    Map<String, dynamic> data,
  ) async {
    
    switch (event) {
        case 'start_match':
          await _handleStartMatch(roomId, round, sessionId, data);
          break;
        case 'completed_initial_peek':
          await _handleCompletedInitialPeek(roomId, round, sessionId, data);
          break;
        case 'draw_card':
          final playerId = _getPlayerIdFromSession(sessionId, roomId);
          if (playerId == null || playerId.isEmpty) {
            server.sendToSession(sessionId, {
              'event': 'error',
              'message': 'Player not in game',
              'room_id': roomId,
            });
            break;
          }
          final gamesMap = _getCurrentGamesMap(roomId);
          await round.handleDrawCard(
            (data['source'] as String?) ?? 'deck',
            playerId: playerId,
            gamesMap: gamesMap,
          );
          break;
        case 'play_card':
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (cardId != null && cardId.isNotEmpty) {
            final playerId = _getPlayerIdFromSession(sessionId, roomId);
            if (playerId == null || playerId.isEmpty) {
              server.sendToSession(sessionId, {
                'event': 'error',
                'message': 'Player not in game',
                'room_id': roomId,
              });
              break;
            }
            final gamesMap = _getCurrentGamesMap(roomId);
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
          
          final actingPlayerId = _getPlayerIdFromSession(sessionId, roomId);
          final firstCardId = (data['first_card_id'] as String?) ?? (data['firstCardId'] as String?);
          final firstPlayerId = (data['first_player_id'] as String?) ?? (data['firstPlayerId'] as String?);
          final secondCardId = (data['second_card_id'] as String?) ?? (data['secondCardId'] as String?);
          final secondPlayerId = (data['second_player_id'] as String?) ?? (data['secondPlayerId'] as String?);
          
          
          
          if (actingPlayerId == null || actingPlayerId.isEmpty) {
            server.sendToSession(sessionId, {
              'event': 'error',
              'message': 'Player not in game',
              'room_id': roomId,
            });
            break;
          }
          
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
              actingPlayerId: actingPlayerId,
              gamesMap: gamesMap,
            );
          } else {
            
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
        case 'call_dutch': // Keep for backward compatibility
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
  }

  /// Initialize match: create base state, players (human/computers), deck, then initialize round
  Future<void> _handleStartMatch(String roomId, DutchGameRound round, String sessionId, Map<String, dynamic> data) async {
    
    
    // Prepare initial state compatible with DutchGameRound
    final stateRoot = _store.getState(roomId);
    final current = Map<String, dynamic>.from(stateRoot['game_state'] as Map<String, dynamic>? ?? {});

    // Guard: only start when phase is waiting_for_players (matches _startMatchForRoom behavior; prevents double start when start_match is sent directly to coordinator)
    final phase = current['phase'] as String?;
    if (phase != null && phase != 'waiting_for_players') {
      
      server.sendToSession(sessionId, {
        'event': 'action_error',
        'message': 'Match already started or invalid phase',
        'game_id': roomId,
        'phase': phase,
      });
      return;
    }

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
    // Game level from state (set in room_created) or room; used for coin fee and stored in game_state
    final gameLevel = current['gameLevel'] as int? ?? roomInfo?.gameLevel;
    final isCoinRequired = current['isCoinRequired'] as bool? ?? true;

    // Auto-create computer players
    // For practice mode: fill to maxPlayers (practice rooms start with "practice_room_")
    // For random join rooms: fill to maxPlayers (indicated by is_random_join flag)
    // For autoStart rooms: fill to maxPlayers (rooms with autoStart=true)
    // For regular multiplayer: only fill to minPlayers (wait for real players to join)
    final isPracticeMode = roomId.startsWith('practice_room_');
    final isRandomJoinRaw = data['is_random_join'];
    
    final isRandomJoin = _parseBoolValue(isRandomJoinRaw, defaultValue: false);
    
    
    final autoStartRaw = roomInfo?.autoStart;
    
    final isAutoStart = _parseBoolValue(autoStartRaw, defaultValue: false);
    
    int needed = (isPracticeMode || isRandomJoin || isAutoStart)
        ? maxPlayers - players.length  // Practice mode, random join, or autoStart: fill to maxPlayers
        : minPlayers - players.length; // Regular multiplayer: only fill to minPlayers
    if (needed < 0) needed = 0;
    
    
    
    // Get existing player names to avoid duplicates
    final existingNames = players.map((p) => (p['name'] ?? '').toString()).toSet();
    int cpuIndexBase = 1;
    
    // Get room difficulty for practice mode (from room or state)
    String practiceDifficulty = 'medium'; // Default fallback
    if (isPracticeMode) {
      // Try to get difficulty from room first
      final roomDifficulty = roomInfo?.difficulty;
      if (roomDifficulty != null && roomDifficulty.isNotEmpty) {
        practiceDifficulty = roomDifficulty.toLowerCase();
        
      } else {
        // Fallback to state
        final stateDifficulty = stateRoot['roomDifficulty'] as String?;
        if (stateDifficulty != null && stateDifficulty.isNotEmpty) {
          practiceDifficulty = stateDifficulty.toLowerCase();
          
        } else {
          
        }
      }
    }
    
    // Skip comp player fetching for practice mode - use simulated CPU players
    if (isPracticeMode) {
      
      // Create simulated CPU players (existing logic)
      while (needed > 0 && players.length < maxPlayers) {
        String name;
        do {
          name = 'Player ${cpuIndexBase++}';
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
          'difficulty': practiceDifficulty,  // Use practice difficulty from lobby selection
        });
        existingNames.add(name);  // Track name to avoid duplicates
        needed--;
      }
    } else {
      // Multiplayer mode: tournament match roster comps first, then accepted_players (create-room), then Flask
      int compPlayersAdded = 0;
      int remainingNeeded = needed;

      final tdRoster = current['tournament_data'] as Map<String, dynamic>? ??
          roomInfo?.tournamentData;
      final List<Map<String, dynamic>> tournamentRosterComps = [];
      final mpr = tdRoster?['match_players'] as List<dynamic>?;
      if (mpr != null) {
        for (final raw in mpr) {
          if (raw is! Map) continue;
          final e = Map<String, dynamic>.from(raw);
          final isComp = e['is_comp_player'] == true || e['isHuman'] == false;
          if (!isComp) continue;
          final uid = (e['user_id'] ?? '').toString();
          if (uid.isEmpty) continue;
          if (players.any((p) => (p['userId']?.toString() ?? '') == uid)) continue;
          tournamentRosterComps.add({
            'user_id': uid,
            'username': (e['username'] ?? 'CompPlayer').toString(),
            'is_comp_player': true,
          });
        }
      }

      // start_match payload often omits accepted_players; roster is on Room from create_room.
      final acceptedPlayersRaw = data['accepted_players'] ?? roomInfo?.acceptedPlayers;
      final List<Map<String, dynamic>> acceptedCompList = (acceptedPlayersRaw is List)
          ? acceptedPlayersRaw
              .whereType<Map<String, dynamic>>()
              .where((e) => e['is_comp_player'] == true)
              .toList()
          : <Map<String, dynamic>>[];

      final List<Map<String, dynamic>> allCompPrefill = [
        ...tournamentRosterComps,
        ...acceptedCompList,
      ];

      if (allCompPrefill.isNotEmpty) {
        
        const defaultRank = 'beginner';
        const defaultDifficulty = 'medium';
        final seenCompUserIds = <String>{};
        for (final comp in allCompPrefill) {
          if (players.length >= maxPlayers) break;
          if (comp['is_comp_player'] != true) continue;
          final userId = (comp['user_id'] ?? '').toString();
          if (userId.isEmpty || seenCompUserIds.contains(userId)) continue;
          seenCompUserIds.add(userId);
          final username = (comp['username'] ?? 'CompPlayer').toString();
          final playerId = 'comp_${userId}_${DateTime.now().microsecondsSinceEpoch}';
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
            'isActive': true,
            'difficulty': defaultDifficulty,
            'rank': defaultRank,
            'level': 1,
            'userId': userId,
            'email': (comp['email'] ?? '').toString(),
            'username': username,
          });
          compPlayersAdded++;
          
        }
        remainingNeeded = needed - compPlayersAdded;
      }

      if (remainingNeeded > 0) {
        
        // Get room difficulty from roomInfo or state, and calculate compatible ranks
        final roomDifficulty = roomInfo?.difficulty ?? stateRoot['roomDifficulty'] as String?;
        List<String>? rankFilter;
        if (roomDifficulty != null) {
          rankFilter = RankMatcher.getCompatibleRanks(roomDifficulty);
          
        } else {
          
        }

      try {
        // Fetch comp players from Flask backend with rank filter
        final compPlayersResponse = await server.pythonClient.getCompPlayers(remainingNeeded, rankFilter: rankFilter);
        final success = compPlayersResponse['success'] as bool? ?? false;
        final compPlayersList = compPlayersResponse['comp_players'] as List<dynamic>? ?? [];
        final returnedCount = compPlayersResponse['count'] as int? ?? 0;
        
        if (success && compPlayersList.isNotEmpty) {
          
          
          // Add comp players to players list
          for (final compPlayerData in compPlayersList) {
            if (compPlayerData is! Map<String, dynamic>) continue;
            if (players.length >= maxPlayers) break;
            
            final userId = compPlayerData['user_id'] as String? ?? '';
            final username = compPlayerData['username'] as String? ?? 'CompPlayer';
            final email = compPlayerData['email'] as String? ?? '';
            final rank = compPlayerData['rank'] as String? ?? 'beginner';
            final level = compPlayerData['level'] as int? ?? 1;
            final profilePicture = compPlayerData['profile_picture'] as String?;
            
            // Map rank to YAML difficulty for AI behavior
            final difficulty = RankMatcher.rankToDifficulty(rank);
            
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
              'difficulty': difficulty,  // Mapped from player rank
              'rank': rank,  // Store player rank for reference
              'level': level,  // Store player level for reference
              'userId': userId,  // Store userId for coin deduction logic
              'email': email,  // Store email for reference
              'username': username,  // Store username for display (name is also username for comp players)
              if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
            });
            
            compPlayersAdded++;
            remainingNeeded--;
            
            
          }
          
          
        } else {
          
          
          // If rank filter was used and no players found, retry without filter
          if (rankFilter != null && rankFilter.isNotEmpty && remainingNeeded > 0) {
            
            try {
              final fallbackResponse = await server.pythonClient.getCompPlayers(remainingNeeded);
              final fallbackSuccess = fallbackResponse['success'] as bool? ?? false;
              final fallbackPlayersList = fallbackResponse['comp_players'] as List<dynamic>? ?? [];
              final fallbackCount = fallbackResponse['count'] as int? ?? 0;
              
              if (fallbackSuccess && fallbackPlayersList.isNotEmpty) {
                
                
                // Add comp players to players list
                for (final compPlayerData in fallbackPlayersList) {
                  if (compPlayerData is! Map<String, dynamic>) continue;
                  if (players.length >= maxPlayers) break;
                  
                  final userId = compPlayerData['user_id'] as String? ?? '';
                  final username = compPlayerData['username'] as String? ?? 'CompPlayer';
                  final email = compPlayerData['email'] as String? ?? '';
                  final rank = compPlayerData['rank'] as String? ?? 'beginner';
                  final level = compPlayerData['level'] as int? ?? 1;
                  final profilePicture = compPlayerData['profile_picture'] as String?;
                  
                  // Map rank to YAML difficulty for AI behavior
                  final difficulty = RankMatcher.rankToDifficulty(rank);
                  
                  final playerId = 'comp_${userId}_${DateTime.now().microsecondsSinceEpoch}';
                  
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
                    'isActive': true,
                    'difficulty': difficulty,  // Mapped from player rank
                    'rank': rank,  // Store player rank for reference
                    'level': level,  // Store player level for reference
                    'userId': userId,
                    'email': email,
                    'username': username,  // Store username for display (name is also username for comp players)
                    if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
                  });
                  
                  compPlayersAdded++;
                  remainingNeeded--;
                }
              }
            } catch (fallbackError) {
              
            }
          }
        }
      } catch (e) {
        
        // Continue to fallback logic below
      }
      }

      // Fallback: Create simulated CPU players for any remaining slots
      if (remainingNeeded > 0) {
        
        
        while (remainingNeeded > 0 && players.length < maxPlayers) {
          String name;
          do {
            name = 'Player ${cpuIndexBase++}';
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
        
        
      }
    }

    // Extract showInstructions from data (practice mode) or default to false
    // This is extracted early so we can use it for deck selection
    final showInstructionsRaw = data['showInstructions'];
    
    final showInstructions = _parseBoolValue(showInstructionsRaw, defaultValue: false);
    
    
    // Build deck and deal 4 cards per player (as in practice)
    // showInstructions=true → use demo_deck
    // showInstructions=false/null → no override, use YAML config default (testing_mode setting)
    final String? deckTypeOverride;
    if (showInstructions) {
      // Instructions ON → use demo deck
      deckTypeOverride = 'demo';
      
    } else {
      // Instructions OFF or not set → no override, use YAML config default
      deckTypeOverride = null;
      
    }
    
    final deckFactory = await YamlDeckFactory.fromFile(roomId, DECK_CONFIG_PATH, deckTypeOverride: deckTypeOverride);
    final List<Card> fullDeck = deckFactory.buildDeck();
    final summary = deckFactory.getSummary();
    
    

    // Helper to convert Card to Map (full data for originalDeck lookup)
    Map<String, dynamic> _cardToMap(Card c) => {
      'cardId': c.cardId,
      'rank': c.rank,
      'suit': c.suit,
      'points': c.points,
      if (c.specialPower != null) 'specialPower': c.specialPower,
    };

    // Helper to create ID-only card (for hands - shows card back)
    // Matches dutch game format: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
    Map<String, dynamic> _cardToIdOnly(Card c) => {
      'cardId': c.cardId,
      'suit': '?',      // Face-down: hide suit
      'rank': '?',      // Face-down: hide rank
      'points': 0,      // Face-down: hide points
    };

    // Load predefined hands configuration if available (for testing e.g. jack swap; controlled by enabled in YAML)
    final predefinedHandsLoader = PredefinedHandsLoader();
    final predefinedHandsConfig = await predefinedHandsLoader.loadConfig();
    final enabledRaw = predefinedHandsConfig['enabled'];
    
    final enabledParsed = _parseBoolValue(enabledRaw, defaultValue: false);
    
    // Use predefined hands when YAML enabled: true (for testing e.g. jack swap), regardless of showInstructions
    bool usePredefinedHands = enabledParsed;
    
    if (usePredefinedHands) {
      
    } else {
      
    }
    
    // Validate predefined hands compatibility with current deck
    if (usePredefinedHands) {
      // Get all ranks available in the current deck
      final availableRanks = fullDeck.map((card) => card.rank).toSet();
      
      // Check if all predefined hands use only cards that exist in the current deck
      final hands = predefinedHandsConfig['hands'] as Map<dynamic, dynamic>?;
      if (hands != null) {
        bool allCardsCompatible = true;
        for (final playerHand in hands.values) {
          if (playerHand is List) {
            for (final cardSpec in playerHand) {
              if (cardSpec is Map) {
                final rank = cardSpec['rank']?.toString();
                if (rank != null && !availableRanks.contains(rank)) {
                  allCardsCompatible = false;
                  
                  break;
                }
              }
            }
            if (!allCardsCompatible) break;
          }
        }
        
        if (!allCardsCompatible) {
          usePredefinedHands = false;
          
        } else {
          
        }
      }
    }
    
    if (usePredefinedHands) {
      
    } else {
      
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
          
          
          // Find and deal the predefined cards from the deck
          for (final cardSpec in predefinedHand) {
            final rank = cardSpec['rank']?.toString();
            final suit = cardSpec['suit']?.toString();
            
            if (rank == null || suit == null) {
              
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
              
            } else {
              
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
            
          }
        } else {
          // No predefined hand for this player, deal randomly
          
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
    // Matches dutch game: discard pile starts with first card from remaining deck
    final discardPile = <Map<String, dynamic>>[];
    if (drawStack.isNotEmpty) {
      final firstCard = drawStack.removeAt(0);
      discardPile.add(_cardToMap(firstCard)); // Full data for discard pile (face-up)
      
    }

    // Remaining draw pile as ID-only card maps (matches dutch game format)
    final drawPileIds = drawStack.map((c) => _cardToIdOnly(c)).toList();

    // showInstructions was already extracted earlier for deck selection
    
    // Display pot: table fee × all seated players (room-wide). Promotional tier is per-user at
    // deduct / Python stats time — it does not reduce match_pot for regular players' UI.
    final coinCost = LevelMatcher.tableLevelToCoinFee(gameLevel, defaultFee: 25);
    final activePlayerCount = players.length;
    final pot = coinCost * activePlayerCount;
    
    
    
    
    // Build updated game_state - set to initial_peek phase
    // Add timer configuration to game_state (game-specific, not room-specific)
    Map<String, dynamic> gameState;
    try {
      
      gameState = <String, dynamic>{
        'gameId': roomId,
        'gameName': 'Dutch Game $roomId',
        'players': players,
        'discardPile': discardPile, // Full data (face-up)
        'drawPile': drawPileIds,    // ID-only (face-down)
        'originalDeck': originalDeckMaps,
        'gameType': 'multiplayer',
        if (gameLevel != null) 'gameLevel': gameLevel,
        'isGameActive': true,
        'phase': 'initial_peek', // Set to initial_peek phase
        'playerCount': players.length,
        'maxPlayers': maxPlayers,
        'minPlayers': minPlayers,
        'showInstructions': showInstructions, // Store instructions switch
        'match_class': 'standard', // Placeholder for future match class system
        'coin_cost_per_player': coinCost,
        'match_pot': pot,
        'isCoinRequired': isCoinRequired,
        'isClearAndCollect': () {
          try {
            final rawValue = data['isClearAndCollect'];
            
            final parsedValue = _parseBoolValue(rawValue, defaultValue: true);
            
            return parsedValue;
          } catch (e, stackTrace) {
            
            
            rethrow;
          }
        }(), // Collection mode flag - false = clear mode (no collection), true = collection mode (default to true for backward compatibility)
        'timerConfig': ServerGameStateCallbackImpl.getAllTimerValues(), // Get timer values from registry (single source of truth)
      };
      // Tournament data from DB (create_room payload) — passed into game state for tournament matches
      final isTournament = data['is_tournament'] == true;
      final tournamentData = data['tournament_data'] as Map<String, dynamic>?;
      if (isTournament) gameState['is_tournament'] = true;
      if (tournamentData != null && tournamentData.isNotEmpty) gameState['tournament_data'] = tournamentData;

      final persistedSeId = current['special_event_id']?.toString();
      final persistedSeModal = current['special_event_end_match_modal'];
      if (persistedSeId != null && persistedSeId.trim().isNotEmpty) {
        gameState['special_event_id'] = persistedSeId.trim();
      }
      if (persistedSeModal is Map && persistedSeModal.isNotEmpty) {
        gameState['special_event_end_match_modal'] =
            Map<String, dynamic>.from(persistedSeModal.map((k, v) => MapEntry(k.toString(), v)));
      }
      
      
      
    } catch (e, stackTrace) {
      
      
      rethrow;
    }

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

    final deductOk = await _deductEntryCoinsOnMatchStart(
      roomId: roomId,
      players: players,
      gameLevel: gameLevel,
      isCoinRequired: isCoinRequired,
      coinCost: coinCost,
      sessionId: sessionId,
    );
    if (!deductOk) {
      return;
    }

    stateRoot['game_state'] = gameState;
    _store.mergeRoot(roomId, stateRoot);

    // Canonical emit path: callback handles validation + broadcast + versioning.
    final callback = ServerGameStateCallbackImpl(roomId, server);
    callback.onGameStateChanged({
      'games': _getCurrentGamesMap(roomId),
    });

    // Start phase-based timer for initial peek phase (only if instructions are not shown)
    if (!showInstructions) {
      _initialPeekTimers[roomId]?.cancel();
      
      // Get timer duration from game state timer configuration
      // Use SSOT for fallback value
      final timerConfig = gameState['timerConfig'] as Map<String, int>? ?? {};
      final allTimerValues = ServerGameStateCallbackImpl.getAllTimerValues();
      final initialPeekTimerDuration = timerConfig['initial_peek'] ?? allTimerValues['initial_peek'] ?? 10;
      
      _initialPeekTimers[roomId] = Timer(Duration(seconds: initialPeekTimerDuration), () {
        _onInitialPeekTimerExpired(roomId, round); // Fire and forget - async handled internally
      });
      
    } else {
      
    }

    // DO NOT call initializeRound() yet - wait for timer expiry or all players complete
    
  }

  /// Authoritative entry-fee deduction via Python (promotional tier skips; [isCoinRequired] false skips economy).
  Future<bool> _deductEntryCoinsOnMatchStart({
    required String roomId,
    required List<Map<String, dynamic>> players,
    required int? gameLevel,
    required bool isCoinRequired,
    required int coinCost,
    required String sessionId,
  }) async {
    if (roomId.startsWith('practice_room_')) {
      return true;
    }
    if (!isCoinRequired) {
      return true;
    }
    final humanMongoIds = <String>[];
    for (final p in players) {
      if (!_isHumanPlayerForEntryCoins(p)) continue;
      final uid = _mongoUserIdFromPlayerMap(p);
      if (uid != null && uid.isNotEmpty) {
        humanMongoIds.add(uid);
      }
    }
    if (humanMongoIds.isEmpty) {
      return true;
    }
    final result = await server.pythonClient.deductGameCoinsService(
      gameId: roomId,
      playerIds: humanMongoIds,
      coins: coinCost,
      gameTableLevel: gameLevel,
      isCoinRequired: isCoinRequired,
    );
    if (result['success'] != true) {
      final msg = result['message']?.toString() ?? result['error']?.toString() ?? 'Coin deduction failed';
      server.sendToSession(sessionId, {
        'event': 'action_error',
        'message': msg,
        'game_id': roomId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return false;
    }
    final warnings = result['warnings'] as List<dynamic>?;
    if (warnings != null &&
        warnings.any((w) => w.toString().contains('Insufficient coins'))) {
      server.sendToSession(sessionId, {
        'event': 'action_error',
        'message': 'Insufficient coins for one or more players',
        'game_id': roomId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return false;
    }
    return true;
  }

  bool _isHumanPlayerForEntryCoins(Map<String, dynamic> p) {
    if (p['is_comp_player'] == true) return false;
    if (p['isHuman'] == false) return false;
    final id = p['id']?.toString() ?? '';
    if (id.startsWith('comp_')) return false;
    return true;
  }

  String? _mongoUserIdFromPlayerMap(Map<String, dynamic> p) {
    final u = p['userId']?.toString() ?? p['user_id']?.toString();
    if (u != null && u.isNotEmpty) return u;
    return null;
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
      
    } catch (e) {
      
    }
  }

  /// Select and store AI peek cards for a computer player
  void _selectAndStoreAIPeekCards(Map<String, dynamic> computerPlayer, Map<String, dynamic> gameState, Random random) {
    final hand = computerPlayer['hand'] as List<dynamic>? ?? [];
    final validHandEntries = <Map<String, dynamic>>[];
    for (var i = 0; i < hand.length; i++) {
      final rawCard = hand[i];
      if (rawCard is! Map<String, dynamic>) {
        continue;
      }
      final cardId = rawCard['cardId']?.toString() ?? '';
      if (cardId.isEmpty) {
        continue;
      }
      validHandEntries.add({
        'handIndex': i,
        'card': rawCard,
      });
    }

    if (validHandEntries.length < 2) {
      
      return;
    }

    // Select 2 random cards
    final selectedEntries = <Map<String, dynamic>>[];
    while (selectedEntries.length < 2) {
      final idx = random.nextInt(validHandEntries.length);
      final picked = validHandEntries[idx];
      if (!selectedEntries.contains(picked)) {
        selectedEntries.add(picked);
      }
    }

    final indices = <int>[
      selectedEntries[0]['handIndex'] as int,
      selectedEntries[1]['handIndex'] as int,
    ];
    final playerId = computerPlayer['id']?.toString() ?? '';
    if (playerId.isEmpty) {
      
      return;
    }

    // Get full card data for both cards from originalDeck
    final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
    final card1IdOnly = selectedEntries[0]['card'] as Map<String, dynamic>;
    final card2IdOnly = selectedEntries[1]['card'] as Map<String, dynamic>;

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
      
      return;
    }

    // Check if collection mode is enabled
    final isClearAndCollectRaw = gameState['isClearAndCollect'];
    
    final isClearAndCollect = _parseBoolValue(isClearAndCollectRaw, defaultValue: false);
    

    // Initialize known_cards structure with robust dynamic conversions.
    final knownCardsRaw = computerPlayer['known_cards'];
    final knownCards = knownCardsRaw is Map
        ? Map<String, dynamic>.from(knownCardsRaw)
        : <String, dynamic>{};
    final playerKnownRaw = knownCards[playerId];
    final playerKnown = playerKnownRaw is Map
        ? Map<String, dynamic>.from(playerKnownRaw)
        : <String, dynamic>{};

    if (isClearAndCollect) {
      // Collection mode: Select one card for collection, store other in known_cards
      // Decide collection rank card using priority logic
      final selectedCardForCollection = _selectCardForCollection(card1, card2, random);

      // Determine which card is NOT the collection card
      final nonCollectionCard = selectedCardForCollection['cardId'] == card1['cardId'] ? card2 : card1;

      // Store only the non-collection card in known_cards with card-ID-based structure and handIndex
      final cardId = nonCollectionCard['cardId'] as String;
      final nonCollectionIndex = nonCollectionCard['cardId'] == card1['cardId'] ? indices[0] : indices[1];
      final cardWithIndex = Map<String, dynamic>.from(nonCollectionCard);
      cardWithIndex['handIndex'] = nonCollectionIndex;
      playerKnown[cardId] = cardWithIndex;
      knownCards[playerId] = playerKnown;
      computerPlayer['known_cards'] = knownCards;

      // Set collection_rank_cards to exactly the one selected card (replace, don't append - ensures no duplicate from store/merge)
      computerPlayer['collection_rank_cards'] = [selectedCardForCollection];
      computerPlayer['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';

      
      
    } else {
      // Clear mode: Store BOTH cards in known_cards (no collection) with handIndex
      final card1Id = card1['cardId'] as String;
      final card2Id = card2['cardId'] as String;
      final c1 = Map<String, dynamic>.from(card1);
      c1['handIndex'] = indices[0];
      final c2 = Map<String, dynamic>.from(card2);
      c2['handIndex'] = indices[1];
      playerKnown[card1Id] = c1;
      playerKnown[card2Id] = c2;
      knownCards[playerId] = playerKnown;
      computerPlayer['known_cards'] = knownCards;

      // Ensure collection_rank_cards is empty and collection_rank is not set in classic mode.
      computerPlayer['collection_rank_cards'] = <Map<String, dynamic>>[];
      computerPlayer.remove('collection_rank');

      
    }

    // Add ID-only cardsToPeek for CPU players (for tracking/logic purposes)
    // CPU players get ID-only format since full data is already in known_cards
    computerPlayer['cardsToPeek'] = [
      {'cardId': card1Id, 'suit': '?', 'rank': '?', 'points': 0},
      {'cardId': card2Id, 'suit': '?', 'rank': '?', 'points': 0},
    ];
    
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

  /// Parse a value that might be bool or string to a bool
  /// Handles JSON serialization where bools can become strings
  bool _parseBoolValue(dynamic value, {bool defaultValue = false}) {
    
    if (value is bool) {
      
      return value;
    }
    if (value is String) {
      final result = value.toLowerCase() == 'true';
      
      return result;
    }
    
    return defaultValue;
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
  Future<void> _handleCompletedInitialPeek(String roomId, DutchGameRound round, String sessionId, Map<String, dynamic> data) async {
    try {
      

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
          
        }
      }

      if (humanPlayer == null || humanPlayer.isEmpty) {
        
        server.sendToSession(sessionId, {
          'event': 'completed_initial_peek_error',
          'room_id': roomId,
          'message': 'Human player not found',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      // Guard: only accept completed_initial_peek while game/player are in initial_peek state.
      final currentPhase = gameState['phase']?.toString() ?? '';
      final playerStatus = humanPlayer['status']?.toString() ?? '';
      if (currentPhase != 'initial_peek' || playerStatus != 'initial_peek') {
        
        server.sendToSession(sessionId, {
          'event': 'completed_initial_peek_acknowledged',
          'room_id': roomId,
          'message': 'Initial peek already resolved; request ignored',
          'ignored': true,
          'reason': 'initial_peek_not_active',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      // Extract card_ids from payload only when initial-peek is active for this player.
      final cardIdsRaw = data['card_ids'];
      final cardIds = <String>[];
      if (cardIdsRaw is List) {
        for (final v in cardIdsRaw) {
          final id = v?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            cardIds.add(id);
          }
        }
      }
      if (cardIds.length != 2) {
        
        server.sendToSession(sessionId, {
          'event': 'completed_initial_peek_error',
          'room_id': roomId,
          'message': 'Invalid card_ids: Expected exactly 2 card IDs',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      

      // Clear any existing cards from previous peeks
      humanPlayer['cardsToPeek'] = <Map<String, dynamic>>[];

      // Get full card data for both card_ids from originalDeck
      final cardsToPeek = <Map<String, dynamic>>[];
      for (final cardId in cardIds) {
        final cardData = _getCardById(gameState, cardId);
        if (cardData == null) {
          
          continue;
        }
        cardsToPeek.add(cardData);
      }

      if (cardsToPeek.length != 2) {
        
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
        
        return;
      }
      final playersInGamesMap = gameData['players'] as List<dynamic>? ?? [];
      final playerInGamesMap = playersInGamesMap.firstWhere(
        (p) => p is Map<String, dynamic> && p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>;
      
      if (playerInGamesMap.isEmpty) {
        
        return;
      }

      // Create callback instance for this room (matching GameRegistry pattern)
      final callback = ServerGameStateCallbackImpl(roomId, server);

      // Shared/public view in store: ID-only cards for everyone.
      final idOnlyCardsToPeek = cardIds.map((cardId) => {
        'cardId': cardId,
        'suit': '?',
        'rank': '?',
        'points': 0,
      }).toList();
      playerInGamesMap['cardsToPeek'] = idOnlyCardsToPeek;

      // Single-pass emit: one room send loop with recipient-scoped private overlay.
      callback.emitGameStateScoped(
        sharedUpdates: {
          'games': currentGames,
        },
        privatePlayerId: playerId,
        privateOverlay: {
          'myCardsToPeek': cardsToPeek,
        },
      );
      
      // Also update the humanPlayer reference for subsequent logic (known_cards, collection_rank, etc.)
      humanPlayer['cardsToPeek'] = cardsToPeek;

      // Check if collection mode is enabled
      final isClearAndCollectRaw = gameState['isClearAndCollect'];
      
      final isClearAndCollect = _parseBoolValue(isClearAndCollectRaw, defaultValue: false);
      

      // Initialize known_cards structure
      final humanKnownCards = humanPlayer['known_cards'] as Map<String, dynamic>? ?? {};
      if (humanKnownCards[playerId] == null) {
        humanKnownCards[playerId] = <String, dynamic>{};
      }

      if (isClearAndCollect) {
        // Collection mode: Select one card for collection, store other in known_cards
        // Auto-select collection rank card for human player (same logic as AI)
        // IMPORTANT: Must select collection card BEFORE storing in known_cards
        // so we can exclude it from known_cards (just like computer players)
        final selectedCardForCollection = _selectCardForCollection(cardsToPeek[0], cardsToPeek[1], Random());
        
        // Determine which card is NOT the collection card
        final nonCollectionCard = selectedCardForCollection['cardId'] == cardsToPeek[0]['cardId'] 
            ? cardsToPeek[1] 
            : cardsToPeek[0];

        // Store only the non-collection card in known_cards with card-ID-based structure and handIndex
        final nonCollectionCardId = nonCollectionCard['cardId'] as String;
        final humanHand = humanPlayer['hand'] as List<dynamic>? ?? [];
        int nonCollectionIndex = -1;
        for (int i = 0; i < humanHand.length; i++) {
          final c = humanHand[i];
          if (c is Map && (c['cardId'] ?? c['id'])?.toString() == nonCollectionCardId) {
            nonCollectionIndex = i;
            break;
          }
        }
        final cardWithIndex = Map<String, dynamic>.from(nonCollectionCard);
        cardWithIndex['handIndex'] = nonCollectionIndex;
        (humanKnownCards[playerId] as Map<String, dynamic>)[nonCollectionCardId] = cardWithIndex;
        humanPlayer['known_cards'] = humanKnownCards;
        // Also update in games map for consistency
        playerInGamesMap['known_cards'] = humanKnownCards;

        final fullCardData = _getCardById(gameState, selectedCardForCollection['cardId'] as String);
        if (fullCardData != null) {
          // Set collection_rank_cards to exactly the one selected card (replace, don't append - ensures no duplicate from store/merge)
          final collectionRankCards = [fullCardData];
          humanPlayer['collection_rank_cards'] = collectionRankCards;
          humanPlayer['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';
          // Also update in games map for consistency
          playerInGamesMap['collection_rank_cards'] = collectionRankCards;
          playerInGamesMap['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';

          
        } else {
          
        }
      } else {
        // Clear mode: Store BOTH cards in known_cards (no collection) with handIndex
        final card1Id = cardsToPeek[0]['cardId'] as String;
        final card2Id = cardsToPeek[1]['cardId'] as String;
        final humanHand = humanPlayer['hand'] as List<dynamic>? ?? [];
        int idx1 = -1, idx2 = -1;
        for (int i = 0; i < humanHand.length; i++) {
          final c = humanHand[i];
          if (c is Map) {
            final id = (c['cardId'] ?? c['id'])?.toString() ?? '';
            if (id == card1Id) idx1 = i;
            if (id == card2Id) idx2 = i;
          }
        }
        final c1 = Map<String, dynamic>.from(cardsToPeek[0]);
        c1['handIndex'] = idx1;
        final c2 = Map<String, dynamic>.from(cardsToPeek[1]);
        c2['handIndex'] = idx2;
        (humanKnownCards[playerId] as Map<String, dynamic>)[card1Id] = c1;
        (humanKnownCards[playerId] as Map<String, dynamic>)[card2Id] = c2;
        humanPlayer['known_cards'] = humanKnownCards;
        // Also update in games map for consistency
        playerInGamesMap['known_cards'] = humanKnownCards;

        // Ensure collection_rank_cards is empty and collection_rank is not set
        humanPlayer['collection_rank_cards'] = <Map<String, dynamic>>[];
        humanPlayer.remove('collection_rank');
        playerInGamesMap['collection_rank_cards'] = <Map<String, dynamic>>[];
        playerInGamesMap.remove('collection_rank');

        
      }

      // Set human player status to WAITING
      humanPlayer['status'] = 'waiting';
      // Also update status in games map for consistency
      playerInGamesMap['status'] = 'waiting';

      // Update game state with known_cards, collection_rank, and status changes
      // The callback methods already updated the store for cardsToPeek, but we need to update
      // the store with the known_cards, collection_rank, and status changes
      _store.setGameState(roomId, gameState);

      // Single-pass status update after peek completion.
      final updatedGames = _getCurrentGamesMap(roomId);
      callback.emitGameStateScoped(
        sharedUpdates: {
          'games': updatedGames,
        },
      );

      

      // Phase completion (clearing cardsToPeek, transition to player_turn) happens only when
      // the initial peek timer expires - same for both clear and clear-and-collect modes.
      // cardsToPeek stays visible until timer expiry so the UI can show the peeked cards.
      

    } catch (e) {
      
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
        
        // Check if player has already completed manually (has cardsToPeek set)
        final cardsToPeek = player['cardsToPeek'] as List<dynamic>? ?? [];
        if (cardsToPeek.length == 2) {
          
          continue; // Player already completed manually
        }
        
        // Check if player has already completed via collection mode
        final collectionRank = player['collection_rank'] as String?;
        final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
        
        if (collectionRank != null && collectionRank.isNotEmpty && collectionRankCards.isNotEmpty) {
          continue; // Player already completed via collection mode
        }
        
        // Player hasn't completed - apply auto logic
        
        _selectAndStoreAIPeekCards(player, gameState, random);
        
        // Set status to waiting (same as when human completes manually)
        player['status'] = 'waiting';
      }
      
      // Update store with modified game state
      _store.setGameState(roomId, gameState);
      
      // Canonical emit path: callback handles validation + broadcast + versioning.
      final callback = ServerGameStateCallbackImpl(roomId, server);
      callback.onGameStateChanged({
        'games': _getCurrentGamesMap(roomId),
      });
      
      
    } catch (e) {
      
    }
  }

  /// Handle initial peek timer expiration
  Future<void> _onInitialPeekTimerExpired(String roomId, DutchGameRound round) async {
    try {
      
      
      // Clear timer reference
      _initialPeekTimers[roomId] = null;
      
      final gameState = _store.getGameState(roomId);
      
      // Process AI initial peeks at end of window (select 2 cards, decide collection rank)
      _processAIInitialPeeks(roomId, gameState);
      
      // Check if all players have completed
      if (!_allPlayersCompletedInitialPeek(roomId)) {
        
        
        // Apply auto logic to remaining human players
        _autoCompleteRemainingHumanPlayers(roomId, gameState);
      }
      
      // Now complete initial peek phase (all players should be done)
      await _completeInitialPeek(roomId, round);
    } catch (e) {
      
    }
  }

  /// Generate a random 6-digit number for action IDs
  String _generateActionId() {
    final random = Random();
    final number = random.nextInt(900000) + 100000; // 100000 to 999999
    return number.toString();
  }

  /// Complete initial peek phase: clear cardsToPeek, set all status='waiting', phase='player_turn', then initialize round
  Future<void> _completeInitialPeek(String roomId, DutchGameRound round) async {
    try {
      final gameState = _store.getGameState(roomId);
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      // Get current games map for action declarations
      final currentGames = _getCurrentGamesMap(roomId);
      final gameData = currentGames[roomId]?['gameData']?['game_state'] as Map<String, dynamic>?;
      if (gameData == null) {
        
        return;
      }
      final playersInGamesMap = gameData['players'] as List<dynamic>? ?? [];

      // Declare initial_peek actions for all players BEFORE clearing cardsToPeek
      for (final player in players) {
        if (player is! Map<String, dynamic>) continue;
        
        final playerId = player['id']?.toString();
        if (playerId == null || playerId.isEmpty) continue;
        
        // Get cardsToPeek data before clearing
        final cardsToPeek = player['cardsToPeek'] as List<dynamic>? ?? [];
        
        if (cardsToPeek.length != 2) {
          
          continue;
        }
        
        // Extract card IDs (works for both ID-only and full card data formats)
        final card1Data = cardsToPeek[0] as Map<String, dynamic>?;
        final card2Data = cardsToPeek[1] as Map<String, dynamic>?;
        if (card1Data == null || card2Data == null) continue;
        
        final card1Id = card1Data['cardId']?.toString();
        final card2Id = card2Data['cardId']?.toString();
        
        if (card1Id == null || card2Id == null) continue;
        
        // Find player in games map FIRST (we need to use the hand from games map, not gameState)
        final playerInGamesMap = playersInGamesMap.firstWhere(
          (p) => p is Map<String, dynamic> && p['id']?.toString() == playerId,
          orElse: () => <String, dynamic>{},
        ) as Map<String, dynamic>;
        
        if (playerInGamesMap.isEmpty) {
          
          continue;
        }
        
        // Find card indices in player's hand FROM GAMES MAP (this is what frontend uses for bounds)
        // CRITICAL: Use hand from playerInGamesMap (not from player) to ensure we match frontend bounds
        final hand = playerInGamesMap['hand'] as List<dynamic>? ?? [];
        // CRITICAL: Reset indices for each player (variables are scoped to loop iteration, but explicit reset for clarity)
        int? card1Index;
        int? card2Index;
        
        
        
        // Search through THIS player's hand to find the card indices
        for (int i = 0; i < hand.length; i++) {
          final card = hand[i];
          if (card is Map<String, dynamic>) {
            final cardId = card['cardId']?.toString();
            if (cardId == card1Id) {
              card1Index = i;
              
            } else if (cardId == card2Id) {
              card2Index = i;
              
            }
          } else if (card is String && card == card1Id) {
            card1Index = i;
            
          } else if (card is String && card == card2Id) {
            card2Index = i;
            
          }
          
          if (card1Index != null && card2Index != null) break;
        }
        
        if (card1Index == null || card2Index == null) {
          
          continue;
        }
        
        // Declare action using queue format (consistent with other actions)
        // CRITICAL: Use card1Index and card2Index calculated for THIS specific player
        final actionName = 'initial_peek_${_generateActionId()}';
        final actionData = {
          'card1Data': {
            'cardIndex': card1Index, // Index in THIS player's hand
            'playerId': playerId,    // THIS player's ID
          },
          'card2Data': {
            'cardIndex': card2Index, // Index in THIS player's hand
            'playerId': playerId,    // THIS player's ID
          },
        };
        
        // Add to action queue (list) instead of replacing
        if (!playerInGamesMap.containsKey('action') || playerInGamesMap['action'] == null) {
          playerInGamesMap['action'] = [];
        }
        if (playerInGamesMap['action'] is! List) {
          // Convert existing single action to list format
          final existingAction = playerInGamesMap['action'];
          final existingActionData = playerInGamesMap['actionData'];
          playerInGamesMap['action'] = [
            {'name': existingAction, 'data': existingActionData}
          ];
          playerInGamesMap.remove('actionData');
        }
        (playerInGamesMap['action'] as List).add({
          'name': actionName,
          'data': actionData,
        });
        
        
      }

      // Clear cardsToPeek for all players (store + games map SSOT)
      for (final player in players) {
        if (player is Map<String, dynamic>) {
          player['cardsToPeek'] = <Map<String, dynamic>>[];
          player['status'] = 'waiting';
        }
      }
      for (final p in playersInGamesMap) {
        if (p is Map<String, dynamic>) {
          p['cardsToPeek'] = <Map<String, dynamic>>[];
        }
      }

      // Set phase to player_turn
      gameState['phase'] = 'player_turn';

      // Update store
      _store.setGameState(roomId, gameState);

      // Fresh games map for emit (includes cleared peek + initial_peek actions)
      final gamesForEmit = _getCurrentGamesMap(roomId);

      // Broadcast phase transition: clear peek slices for every client + games map
      final callback = ServerGameStateCallbackImpl(roomId, server);
      callback.onGameStateChanged({
        'games': gamesForEmit,
        'myCardsToPeek': <Map<String, dynamic>>[],
        'cards_to_peek': <dynamic>[],
      });

      

      // NOW initialize the round (starts actual gameplay) - await to ensure factory is loaded
      await round.initializeRound();
    } catch (e) {
      
    }
  }

  /// Cleanup resources for a room
  void cleanup(String roomId) {
    _initialPeekTimers[roomId]?.cancel();
    _initialPeekTimers.remove(roomId);
  }
}


