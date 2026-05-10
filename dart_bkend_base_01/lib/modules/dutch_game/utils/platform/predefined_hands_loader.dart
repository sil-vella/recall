import 'dart:io';
import 'package:yaml/yaml.dart';

/// Predefined Hands Loader for Testing
///
/// This class provides functionality to load predefined hands configuration
/// for testing purposes in the Dutch game.
class PredefinedHandsLoader {
  /// Load the predefined hands configuration from YAML file
  ///
  /// Returns a Map containing 'enabled' flag and 'hands' data
  Future<Map<String, dynamic>> loadConfig() async {
    try {
      // Backend: attempt to read from a local file if present
      final file = File('lib/modules/dutch_game/config/predefined_hands.yaml');
      if (!file.existsSync()) {
        return {'enabled': false, 'hands': {}};
      }
      final yamlString = await file.readAsString();
      final yamlMap = loadYaml(yamlString);
      final config = Map<String, dynamic>.from(yamlMap as Map);
      return config;
    } catch (e) {
      // Return disabled config if file doesn't exist
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
      return null;
    }

    return hand.map((card) => {
      'rank': card['rank'].toString(),
      'suit': card['suit'].toString(),
    }).toList();
  }
}
