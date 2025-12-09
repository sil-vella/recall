import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

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
    _logger.info('🌐 Dart: Calling $baseUrl/public/cleco/update-game-stats', isOn: LOGGING_SWITCH);
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/cleco/update-game-stats'),
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
}
