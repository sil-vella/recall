import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true; // Enabled for rank-based matching, comp player testing, and registration differences

class PythonApiClient {
  final String baseUrl;
  final Logger _logger = Logger();
  
  PythonApiClient({required this.baseUrl});
  
  /// Validate JWT token with Python backend
  Future<Map<String, dynamic>> validateToken(String token) async {
    _logger.auth('🔍 Dart: Starting token validation with Python API', isOn: LOGGING_SWITCH);
    _logger.auth('🌐 Dart: Calling $baseUrl/api/auth/validate', isOn: LOGGING_SWITCH);
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );
      
      _logger.auth('📡 Dart: HTTP response status: ${response.statusCode}', isOn: LOGGING_SWITCH);
      _logger.auth('📦 Dart: Response body: ${response.body}', isOn: LOGGING_SWITCH);
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        _logger.auth('✅ Dart: Token validation successful', isOn: LOGGING_SWITCH);
        return result;
      } else {
        _logger.auth('❌ Dart: HTTP error ${response.statusCode}: ${response.body}', isOn: LOGGING_SWITCH);
        return {'valid': false, 'error': 'Invalid token'};
      }
    } catch (e) {
      _logger.auth('❌ Dart: Network error validating token: $e', isOn: LOGGING_SWITCH);
      return {'valid': false, 'error': 'Connection failed'};
    }
  }
  
  /// Update game statistics for players after a game ends
  Future<Map<String, dynamic>> updateGameStats(List<Map<String, dynamic>> gameResults) async {
    _logger.info('📊 Dart: Updating game statistics for ${gameResults.length} player(s)', isOn: LOGGING_SWITCH);
    _logger.info('🌐 Dart: Calling $baseUrl/public/dutch/update-game-stats', isOn: LOGGING_SWITCH);
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/dutch/update-game-stats'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'game_results': gameResults,
        }),
      );
      
      _logger.info('📡 Dart: HTTP response status: ${response.statusCode}', isOn: LOGGING_SWITCH);
      _logger.info('📦 Dart: Response body: ${response.body}', isOn: LOGGING_SWITCH);
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        _logger.info('✅ Dart: Game statistics updated successfully', isOn: LOGGING_SWITCH);
        return result;
      } else {
        _logger.error('❌ Dart: HTTP error ${response.statusCode}: ${response.body}', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': 'Failed to update game statistics',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      _logger.error('❌ Dart: Network error updating game stats: $e', isOn: LOGGING_SWITCH);
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
    _logger.info('🤖 Dart: Requesting $count comp player(s) from Python API' + (rankFilter != null ? ' with rank filter: $rankFilter' : ''), isOn: LOGGING_SWITCH);
    _logger.info('🌐 Dart: Calling $baseUrl/public/dutch/get-comp-players', isOn: LOGGING_SWITCH);
    
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
      
      _logger.info('📡 Dart: HTTP response status: ${response.statusCode}', isOn: LOGGING_SWITCH);
      _logger.info('📦 Dart: Response body: ${response.body}', isOn: LOGGING_SWITCH);
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        final compPlayers = result['comp_players'] as List<dynamic>? ?? [];
        final returnedCount = result['count'] as int? ?? 0;
        
        _logger.info('✅ Dart: Retrieved $returnedCount comp player(s) (requested $count)', isOn: LOGGING_SWITCH);
        
        return {
          'success': success,
          'comp_players': compPlayers,
          'count': returnedCount,
          'requested_count': count,
          'available_count': result['available_count'] as int? ?? returnedCount,
          'message': result['message'] as String?,
        };
      } else {
        _logger.error('❌ Dart: HTTP error ${response.statusCode}: ${response.body}', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': 'Failed to retrieve comp players',
          'status_code': response.statusCode,
          'comp_players': <Map<String, dynamic>>[],
          'count': 0,
        };
      }
    } catch (e) {
      _logger.error('❌ Dart: Network error retrieving comp players: $e', isOn: LOGGING_SWITCH);
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
    _logger.info('👤 Dart: Requesting user profile for userId: $userId', isOn: LOGGING_SWITCH);
    _logger.info('🌐 Dart: Calling $baseUrl/public/users/profile', isOn: LOGGING_SWITCH);
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/users/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
        }),
      );
      
      _logger.info('📡 Dart: HTTP response status: ${response.statusCode}', isOn: LOGGING_SWITCH);
      _logger.info('📦 Dart: Response body: ${response.body}', isOn: LOGGING_SWITCH);
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final success = result['success'] as bool? ?? false;
        
        if (success) {
          final accountType = result['account_type'] as String? ?? 'unknown';
          final username = result['username'] as String? ?? 'unknown';
          _logger.info('✅ Dart: Retrieved user profile for userId: $userId, username: $username, account_type: $accountType', isOn: LOGGING_SWITCH);
          return result;
        } else {
          _logger.warning('⚠️ Dart: API returned success=false: ${result['error']}', isOn: LOGGING_SWITCH);
          return {
            'success': false,
            'error': result['error'] ?? 'Failed to retrieve user profile',
          };
        }
      } else {
        _logger.error('❌ Dart: HTTP error ${response.statusCode}: ${response.body}', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': 'Failed to retrieve user profile',
          'status_code': response.statusCode,
        };
      }
    } catch (e) {
      _logger.error('❌ Dart: Network error retrieving user profile: $e', isOn: LOGGING_SWITCH);
      return {
        'success': false,
        'error': 'Connection failed',
        'message': e.toString(),
      };
    }
  }
}
