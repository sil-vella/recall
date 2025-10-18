import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:recall/tools/logging/logger.dart';

/// Predefined Hands Loader for Testing
/// 
/// This class provides functionality to load predefined hands configuration
/// for testing purposes in the Recall game.
class PredefinedHandsLoader {
  /// Load the predefined hands configuration from YAML file
  /// 
  /// Returns a Map containing 'enabled' flag and 'hands' data
  Future<Map<String, dynamic>> loadConfig() async {
    try {
      final yamlString = await rootBundle.loadString('assets/predefined_hands.yaml');
      final yamlMap = loadYaml(yamlString);
      final config = Map<String, dynamic>.from(yamlMap);
      
      Logger().info('Loaded predefined hands config: enabled=${config['enabled']}', isOn: true);
      return config;
    } catch (e) {
      // Return disabled config if file doesn't exist
      Logger().warning('Predefined hands config file not found, using default (disabled)');
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
      Logger().debug('No predefined hand found for player $playerIndex');
      return null;
    }
    
    Logger().debug('Found predefined hand for player $playerIndex: ${hand.length} cards');
    return hand.map((card) => {
      'rank': card['rank'].toString(),
      'suit': card['suit'].toString(),
    }).toList();
  }
}
