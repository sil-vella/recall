import 'package:flutter_test/flutter_test.dart';
import 'package:recall/modules/recall_game/game_logic/practice_match/utils/predefined_hands_loader.dart';

void main() {
  group('PredefinedHandsLoader Tests', () {
    test('should load config with enabled false by default', () async {
      final loader = PredefinedHandsLoader();
      final config = await loader.loadConfig();
      
      expect(config['enabled'], false);
      expect(config['hands'], isA<Map>());
    });
    
    test('should return null for player hand when disabled', () async {
      final loader = PredefinedHandsLoader();
      final config = await loader.loadConfig();
      
      final hand = loader.getHandForPlayer(config, 0);
      expect(hand, isNull);
    });
    
    test('should return null for non-existent player', () async {
      final loader = PredefinedHandsLoader();
      final config = {'enabled': true, 'hands': {}};
      
      final hand = loader.getHandForPlayer(config, 0);
      expect(hand, isNull);
    });
  });
}
