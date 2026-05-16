import 'dart:convert';
import 'package:http/http.dart' as http;
import '../modules/dutch_game/backend_core/utils/progression_config_store.dart';
import '../utils/config.dart';

class PythonApiClient {
  final String baseUrl;
  
  PythonApiClient({required this.baseUrl});
  
    /// Validate JWT token with Python backend (service endpoint: requires X-Service-Key)
    Future<Map<String, dynamic>> validateToken(String token) async {
    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/auth/validate'),
        headers: headers,
        body: jsonEncode({'token': token}),
      );
      
      
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        return result;
      } else {
        
        return {'valid': false, 'error': 'Invalid token'};
      }
    } catch (e) {
      
      return {'valid': false, 'error': 'Connection failed'};
    }
  }
  
  /// Update game statistics for players after a game ends (service endpoint: X-Service-Key auth).
  /// [isTournament] and [tournamentData] are read from game state and sent when the match was a tournament.
  Future<Map<String, dynamic>> updateGameStats(
    List<Map<String, dynamic>> gameResults, {
    bool isTournament = false,
    Map<String, dynamic>? tournamentData,
    String? roomId,
    /// When false, Python skips winner pot credit (with promotional tier in same SSOT).
    bool? isCoinRequired,
    /// Resolves event_win achievements in Python when the match was a special-event room.
    String? specialEventId,
  }) async {
    

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    final body = <String, dynamic>{
      'game_results': gameResults,
      if (roomId != null && roomId.isNotEmpty) 'room_id': roomId,
      if (isTournament) 'is_tournament': true,
      if (isTournament && tournamentData != null && tournamentData.isNotEmpty) 'tournament_data': tournamentData,
      if (isCoinRequired != null) 'is_coin_required': isCoinRequired,
      if (specialEventId != null && specialEventId.isNotEmpty) 'special_event_id': specialEventId,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/update-game-stats'),
        headers: headers,
        body: jsonEncode(body),
      );
      
      
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        return result;
      } else {
        
        return {
          'success': false,
          'error': 'Failed to update game statistics',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }
  
  /// Get computer players from Flask backend
  /// [count] Number of comp players to retrieve
  /// [rankFilter] Optional list of compatible ranks to filter by
  Future<Map<String, dynamic>> getCompPlayers(int count, {List<String>? rankFilter}) async {
    
    
    try {
      final requestBody = <String, dynamic>{
        'count': count,
      };
      if (rankFilter != null && rankFilter.isNotEmpty) {
        requestBody['rank_filter'] = rankFilter;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/public/dutch/get-comp-players'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        final compPlayers = result['comp_players'] as List<dynamic>? ?? [];
        final returnedCount = result['count'] as int? ?? 0;
        
        
        
        return {
          'success': success,
          'comp_players': compPlayers,
          'count': returnedCount,
          'requested_count': count,
          'available_count': result['available_count'] as int? ?? returnedCount,
          'message': result['message'] as String?,
        };
      } else {
        
        return {
          'success': false,
          'error': 'Failed to retrieve comp players',
          'status_code': response.statusCode,
          'comp_players': <Map<String, dynamic>>[],
          'count': 0,
        };
      }
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
        'comp_players': <Map<String, dynamic>>[],
        'count': 0,
      };
    }
  }
  
  /// Load declarative progression config from Python (no user_id).
  Future<bool> fetchInitConfig() async {
    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    try {
      final body = <String, dynamic>{};
      final rev = ProgressionConfigStore.cachedRevision;
      if (rev != null && rev.isNotEmpty) {
        body['client_progression_config_revision'] = rev;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/get-init-data'),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) {
        ProgressionConfigStore.ensureEnvFallback();
        return false;
      }
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (result['success'] != true) {
        ProgressionConfigStore.ensureEnvFallback();
        return false;
      }
      final payload = result['progression_config'];
      if (payload is Map<String, dynamic>) {
        ProgressionConfigStore.applyDocument(
          Map<String, dynamic>.from(payload),
          revision: result['progression_config_revision']?.toString(),
        );
      } else {
        final revOnly = result['progression_config_revision']?.toString().trim();
        if (revOnly != null && revOnly.isNotEmpty) {
          ProgressionConfigStore.updateRevisionOnly(revOnly);
        }
      }
      return true;
    } catch (_) {
      ProgressionConfigStore.ensureEnvFallback();
      return false;
    }
  }

  /// Get user dutch-game stats (coins, subscription_tier) by userId for join/create room coins check.
  /// Service endpoint: X-Service-Key auth.
  Future<Map<String, dynamic>> getUserStatsForJoin(String userId) async {
    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    try {
      final body = <String, dynamic>{'user_id': userId};
      final rev = ProgressionConfigStore.cachedRevision;
      if (rev != null && rev.isNotEmpty) {
        body['client_progression_config_revision'] = rev;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/get-init-data'),
        headers: headers,
        body: jsonEncode(body),
      );

      

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        if (success) {
          final data = result['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final coins = data['coins'] as int?;
          final tier = (data['subscription_tier'] as String?)?.trim() ?? '';
          final inventory = data['inventory'] as Map<String, dynamic>? ?? <String, dynamic>{};
          
          return {
            'success': true,
            'coins': coins,
            'subscription_tier': tier,
            'inventory': inventory,
          };
        }
        return {
          'success': false,
          'error': result['error'] ?? 'Failed to get user stats',
        };
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}',
        'status_code': response.statusCode,
      };
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }

  /// Authoritative entry-fee deduction when Dart WS starts a match (service endpoint: X-Service-Key).
  /// Same SSOT as `/userauth/dutch/deduct-game-coins`: promotional tier skips; [is_coin_required] false skips economy.
  Future<Map<String, dynamic>> deductGameCoinsService({
    required String gameId,
    required List<String> playerIds,
    required int coins,
    int? gameTableLevel,
    bool isCoinRequired = true,
  }) async {
    

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    final body = <String, dynamic>{
      'game_id': gameId,
      'player_ids': playerIds,
      'coins': coins,
      if (gameTableLevel != null) 'game_table_level': gameTableLevel,
      'is_coin_required': isCoinRequired,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/deduct-game-coins'),
        headers: headers,
        body: jsonEncode(body),
      );

      

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        return result;
      }
      Map<String, dynamic>? errBody;
      try {
        errBody = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {}
      return {
        'success': false,
        'error': errBody?['error'] ?? errBody?['message'] ?? 'HTTP ${response.statusCode}',
        'status_code': response.statusCode,
        'body': response.body,
      };
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }

  /// Before rematch reset: send full store + room snapshot to Python for tournament persistence (service key).
  /// [initialMatchGameResults] — finished casual game rows (same shape as [updateGameStats] `game_results`);
  /// Python stores them as `match_index` 1 `completed` when creating the tournament.
  Future<Map<String, dynamic>> notifyRematchTournamentSnapshot({
    required String roomId,
    required Map<String, dynamic> storeSnapshot,
    required Map<String, dynamic> roomSnapshot,
    List<Map<String, dynamic>>? initialMatchGameResults,
  }) async {
    

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    final body = <String, dynamic>{
      'room_id': roomId,
      'store_snapshot': storeSnapshot,
      'room_snapshot': roomSnapshot,
      if (initialMatchGameResults != null && initialMatchGameResults.isNotEmpty)
        'initial_match_game_results': initialMatchGameResults,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/rematch-tournament-snapshot'),
        headers: headers,
        body: jsonEncode(body),
      );

      

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        return result;
      }
      return {
        'success': false,
        'error': 'rematch-tournament-snapshot failed',
        'status_code': response.statusCode,
        'body': response.body,
      };
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }

  /// Attach a room_id to a tournament match (service endpoint: X-Service-Key auth).
  /// Called by Dart backend when a tournament room's match starts so Python DB stays in sync.
  Future<Map<String, dynamic>> attachTournamentMatchRoom({
    required String tournamentId,
    required String roomId,
    dynamic matchIndex,
  }) async {
    

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    final body = <String, dynamic>{
      'tournament_id': tournamentId,
      'room_id': roomId,
    };
    if (matchIndex != null) {
      body['match_index'] = matchIndex;
      body['match_id'] = matchIndex; // Python accepts either
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/attach-tournament-match-room'),
        headers: headers,
        body: jsonEncode(body),
      );

      

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        
        return result;
      }
      return {
        'success': false,
        'error': 'Failed to attach room to tournament match',
        'status_code': response.statusCode,
        'body': response.body,
      };
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }

  /// Get user profile data (full name, profile picture) by userId
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/users/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
        }),
      );
      
      
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        
        if (success) {
          final accountType = result['account_type'] as String? ?? 'unknown';
          final username = result['username'] as String? ?? 'unknown';
          
          return result;
        } else {
          
          return {
            'success': false,
            'error': result['error'] ?? 'Failed to retrieve user profile',
          };
        }
      } else {
        
        return {
          'success': false,
          'error': 'Failed to retrieve user profile',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }
}
