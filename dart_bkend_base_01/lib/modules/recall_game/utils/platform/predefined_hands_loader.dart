import 'dart:io';
import 'package:yaml/yaml.dart';
import 'shared_imports.dart';

const bool LOGGING_SWITCH = false;


/// Predefined Hands Loader for Testing
/// 
/// This class provides functionality to load predefined hands configuration
/// for testing purposes in the Recall game.
class PredefinedHandsLoader {
  final Logger _logger = Logger();
  /// Load the predefined hands configuration from YAML file
  /// 
  /// Returns a Map containing 'enabled' flag and 'hands' data
  Future<Map<String, dynamic>> loadConfig() async {
    try {
      // Backend: attempt to read from a local file if present
      final file = File('lib/modules/recall_game/config/predefined_hands.yaml');
      if (!file.existsSync()) {
        return {'enabled': false, 'hands': {}};
      }
      final yamlString = await file.readAsString();
      final yamlMap = loadYaml(yamlString);
      final config = Map<String, dynamic>.from(yamlMap as Map);
      _logger.info('Loaded predefined hands config: enabled=${config['enabled']}', isOn: LOGGING_SWITCH);
      return config;
    } catch (e) {
      // Return disabled config if file doesn't exist
      _logger.warning('Predefined hands config load failed, defaulting to disabled: $e', isOn: LOGGING_SWITCH);
      return {'enabled': false, 'hands': {}};
    }
  }
  
  /// Get predefined hand for a specific player
  /// 
  /// [config] Configuration dictionary from loadConfig()
  /// [playerIndex] Index of the player (0-based)
  /// 
  /// Returns a List of card specifications or null if no predefined hand
  List<Map<String, String>>? getHandForPlayer(Map<String, dynamic> config, int playerIndex) {
    if (!config['enabled']) return null;
    
    final hands = config['hands'] as Map<dynamic, dynamic>?;
    if (hands == null) return null;
    
    final playerKey = 'player_$playerIndex';
    final hand = hands[playerKey] as List<dynamic>?;
    
    if (hand == null) {
      _logger.debug('No predefined hand found for player $playerIndex', isOn: LOGGING_SWITCH);
      return null;
    }
    
    _logger.debug('Found predefined hand for player $playerIndex: ${hand.length} cards', isOn: LOGGING_SWITCH);
    return hand.map((card) => {
      'rank': card['rank'].toString(),
      'suit': card['suit'].toString(),
    }).toList();
  }
}
