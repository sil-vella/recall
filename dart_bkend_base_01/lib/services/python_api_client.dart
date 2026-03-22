import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/config.dart';
import '../utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true; // Coin check: get-user-stats + WS auth paths (enable-logging-switch.mdc)

class PythonApiClient {
  final String baseUrl;
  final Logger _logger = Logger();
  
  PythonApiClient({required this.baseUrl});
  
    /// Validate JWT token with Python backend (service endpoint: requires X-Service-Key)
    Future<Map<String, dynamic>> validateToken(String token) async {
    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    // Always log service key config (no key value) so server.log can verify env is set
    _logger.auth(
      'Dart service key: usePythonServiceKey=$useKey, key_configured=${serviceKey.isNotEmpty}',
    );
    if (LOGGING_SWITCH) {
      _logger.auth('🔍 Dart: Starting token validation with Python API');
      _logger.auth('🌐 Dart: Calling $baseUrl/service/auth/validate');
    }
    if (useKey && serviceKey.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.auth('⚠️ Dart: USE_PYTHON_SERVICE_KEY is on but DART_BACKEND_SERVICE_KEY not set; Python may reject the request');
      }
    }

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
      
      if (LOGGING_SWITCH) {
        _logger.auth('📡 Dart: HTTP response status: ${response.statusCode}');
        _logger.auth('📦 Dart: Response body: ${response.body}');
      }
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (LOGGING_SWITCH) {
          _logger.auth('✅ Dart: Token validation successful');
        }
        return result;
      } else {
        if (LOGGING_SWITCH) {
          _logger.auth('❌ Dart: HTTP error ${response.statusCode}: ${response.body}');
        }
        return {'valid': false, 'error': 'Invalid token'};
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.auth('❌ Dart: Network error validating token: $e');
      }
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
  }) async {
    if (LOGGING_SWITCH) {
      _logger.info('📊 Dart: Updating game statistics for ${gameResults.length} player(s), isTournament=$isTournament');
      _logger.info('🌐 Dart: Calling $baseUrl/service/dutch/update-game-stats');
    }

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    if (useKey && serviceKey.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ Dart: USE_PYTHON_SERVICE_KEY is on but DART_BACKEND_SERVICE_KEY not set; Python may reject the request');
      }
    }

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
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/update-game-stats'),
        headers: headers,
        body: jsonEncode(body),
      );
      
      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: HTTP response status: ${response.statusCode}');
        _logger.info('📦 Dart: Response body: ${response.body}');
      }
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (LOGGING_SWITCH) {
          _logger.info('✅ Dart: Game statistics updated successfully');
        }
        return result;
      } else {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Dart: HTTP error ${response.statusCode}: ${response.body}');
        }
        return {
          'success': false,
          'error': 'Failed to update game statistics',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error updating game stats: $e');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('🤖 Dart: Requesting $count comp player(s) from Python API' + (rankFilter != null ? ' with rank filter: $rankFilter' : ''));
      _logger.info('🌐 Dart: Calling $baseUrl/public/dutch/get-comp-players');
    }
    
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
      
      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: HTTP response status: ${response.statusCode}');
        _logger.info('📦 Dart: Response body: ${response.body}');
      }
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        final compPlayers = result['comp_players'] as List<dynamic>? ?? [];
        final returnedCount = result['count'] as int? ?? 0;
        
        if (LOGGING_SWITCH) {
          _logger.info('✅ Dart: Retrieved $returnedCount comp player(s) (requested $count)');
        }
        
        return {
          'success': success,
          'comp_players': compPlayers,
          'count': returnedCount,
          'requested_count': count,
          'available_count': result['available_count'] as int? ?? returnedCount,
          'message': result['message'] as String?,
        };
      } else {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Dart: HTTP error ${response.statusCode}: ${response.body}');
        }
        return {
          'success': false,
          'error': 'Failed to retrieve comp players',
          'status_code': response.statusCode,
          'comp_players': <Map<String, dynamic>>[],
          'count': 0,
        };
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error retrieving comp players: $e');
      }
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
        'comp_players': <Map<String, dynamic>>[],
        'count': 0,
      };
    }
  }
  
  /// Get user dutch-game stats (coins, subscription_tier) by userId for join/create room coins check.
  /// Service endpoint: X-Service-Key auth.
  Future<Map<String, dynamic>> getUserStatsForJoin(String userId) async {
    if (LOGGING_SWITCH) {
      _logger.info('📊 Dart: Requesting user stats for join check, userId: $userId');
      _logger.info('🌐 Dart: Calling $baseUrl/service/dutch/get-user-stats');
    }

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/get-user-stats'),
        headers: headers,
        body: jsonEncode({'user_id': userId}),
      );

      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: get-user-stats response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        if (success) {
          final data = result['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final coins = data['coins'] as int?;
          final tier = (data['subscription_tier'] as String?)?.trim() ?? '';
          if (LOGGING_SWITCH) {
            _logger.info('📊 Dart: get-user-stats success userId=$userId coins=$coins subscription_tier="$tier"');
          }
          return {
            'success': true,
            'coins': coins,
            'subscription_tier': tier,
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
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error get-user-stats: $e');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info(
        '📊 Dart: deduct-game-coins (service) gameId=$gameId players=${playerIds.length} coins=$coins table=$gameTableLevel coinReq=$isCoinRequired',
      );
      _logger.info('🌐 Dart: Calling $baseUrl/service/dutch/deduct-game-coins');
    }

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

      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: deduct-game-coins (service) status: ${response.statusCode}');
      }

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
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error deduct-game-coins (service): $e');
      }
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }

  /// Before rematch reset: send full store + room snapshot to Python for tournament persistence (service key).
  /// Handler currently logs payload only.
  Future<Map<String, dynamic>> notifyRematchTournamentSnapshot({
    required String roomId,
    required Map<String, dynamic> storeSnapshot,
    required Map<String, dynamic> roomSnapshot,
  }) async {
    if (LOGGING_SWITCH) {
      _logger.info(
        '🏟 Dart: rematch-tournament-snapshot room_id=$roomId store_keys=${storeSnapshot.keys.toList()}',
      );
      _logger.info('🌐 Dart: Calling $baseUrl/service/dutch/rematch-tournament-snapshot');
    }

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    if (useKey && serviceKey.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning(
          '⚠️ Dart: USE_PYTHON_SERVICE_KEY is on but DART_BACKEND_SERVICE_KEY not set; Python may reject the request',
        );
      }
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (serviceKey.isNotEmpty) 'X-Service-Key': serviceKey,
    };

    final body = <String, dynamic>{
      'room_id': roomId,
      'store_snapshot': storeSnapshot,
      'room_snapshot': roomSnapshot,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/rematch-tournament-snapshot'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: rematch-tournament-snapshot status: ${response.statusCode}');
        _logger.info('📦 Dart: rematch-tournament-snapshot body: ${response.body}');
      }

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
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error rematch-tournament-snapshot: $e');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('🏟 Dart: attach-tournament-match-room tournament_id=$tournamentId match_index=$matchIndex room_id=$roomId');
      _logger.info('🌐 Dart: Calling $baseUrl/service/dutch/attach-tournament-match-room');
    }

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
    if (useKey && serviceKey.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ Dart: USE_PYTHON_SERVICE_KEY is on but DART_BACKEND_SERVICE_KEY not set; Python may reject the request');
      }
    }

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

      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: attach-tournament-match-room response status: ${response.statusCode}');
        _logger.info('📦 Dart: Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        if (success && LOGGING_SWITCH) {
          _logger.info('✅ Dart: attach-tournament-match-room success');
        }
        return result;
      }
      return {
        'success': false,
        'error': 'Failed to attach room to tournament match',
        'status_code': response.statusCode,
        'body': response.body,
      };
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error attach-tournament-match-room: $e');
      }
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }

  /// Get user profile data (full name, profile picture) by userId
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    if (LOGGING_SWITCH) {
      _logger.info('👤 Dart: Requesting user profile for userId: $userId');
      _logger.info('🌐 Dart: Calling $baseUrl/public/users/profile');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/users/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
        }),
      );
      
      if (LOGGING_SWITCH) {
        _logger.info('📡 Dart: HTTP response status: ${response.statusCode}');
        _logger.info('📦 Dart: Response body: ${response.body}');
      }
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        
        if (success) {
          final accountType = result['account_type'] as String? ?? 'unknown';
          final username = result['username'] as String? ?? 'unknown';
          if (LOGGING_SWITCH) {
            _logger.info('✅ Dart: Retrieved user profile for userId: $userId, username: $username, account_type: $accountType');
          }
          return result;
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Dart: API returned success=false: ${result['error']}');
          }
          return {
            'success': false,
            'error': result['error'] ?? 'Failed to retrieve user profile',
          };
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Dart: HTTP error ${response.statusCode}: ${response.body}');
        }
        return {
          'success': false,
          'error': 'Failed to retrieve user profile',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Dart: Network error retrieving user profile: $e');
      }
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }
}
