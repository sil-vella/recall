import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/config.dart';
import '../utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false; // Enabled for login/account creation debugging (token validation, game stats)

class PythonApiClient {
  final String baseUrl;
  final Logger _logger = Logger();
  
  PythonApiClient({required this.baseUrl});
  
  /// Validate JWT token with Python backend (service endpoint: requires X-Service-Key)
  Future<Map<String, dynamic>> validateToken(String token) async {
    if (LOGGING_SWITCH) {
      _logger.auth('🔍 Dart: Starting token validation with Python API');
      _logger.auth('🌐 Dart: Calling $baseUrl/service/auth/validate');
    }

    final useKey = Config.usePythonServiceKey;
    final serviceKey = useKey ? Config.pythonServiceKey : '';
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
  
  /// Update game statistics for players after a game ends (service endpoint: X-Service-Key auth)
  Future<Map<String, dynamic>> updateGameStats(List<Map<String, dynamic>> gameResults) async {
    if (LOGGING_SWITCH) {
      _logger.info('📊 Dart: Updating game statistics for ${gameResults.length} player(s)');
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

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/service/dutch/update-game-stats'),
        headers: headers,
        body: jsonEncode({
          'game_results': gameResults,
        }),
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
