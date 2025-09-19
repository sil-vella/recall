#!/usr/bin/env python3
"""
Simple test script for Dart Game Service Integration
"""

import sys
import os
import time
import json

# Add the python_base_04 directory to the Python path
sys.path.append(os.path.join(os.path.dirname(__file__), '../../../../..'))

# Import the dart subprocess manager directly
from core.modules.recall_game.game_logic.dart_services.dart_subprocess_manager import dart_subprocess_manager

def test_dart_service():
    """Test the Dart service with basic operations"""
    print("Testing Dart Game Service...")
    
    # Test health check
    print("1. Testing health check...")
    if dart_subprocess_manager.health_check():
        print("   ✅ Health check passed")
    else:
        print("   ❌ Health check failed")
        return False
    
    # Test game creation
    print("2. Testing game creation...")
    game_id = "test_game_001"
    if dart_subprocess_manager.create_game(game_id, max_players=4, min_players=2):
        print(f"   ✅ Game {game_id} created")
    else:
        print(f"   ❌ Failed to create game {game_id}")
        return False
    
    # Test player joining
    print("3. Testing player joining...")
    if dart_subprocess_manager.join_game(game_id, "player_001", "Test Player", "human"):
        print("   ✅ Player joined game")
    else:
        print("   ❌ Failed to join player")
        return False
    
    # Test computer player joining
    print("4. Testing computer player joining...")
    if dart_subprocess_manager.join_game(game_id, "computer_001", "AI Player", "computer", "medium"):
        print("   ✅ Computer player joined game")
    else:
        print("   ❌ Failed to join computer player")
        return False
    
    # Test player action
    print("5. Testing player action...")
    action_data = {
        'card_id': 'test_card_001',
        'card_index': 0
    }
    if dart_subprocess_manager.player_action(game_id, "session_001", "play_card", action_data):
        print("   ✅ Player action sent")
    else:
        print("   ❌ Failed to send player action")
        return False
    
    # Test cleanup
    print("6. Testing game cleanup...")
    if dart_subprocess_manager.cleanup_game(game_id):
        print("   ✅ Game cleaned up")
    else:
        print("   ❌ Failed to cleanup game")
        return False
    
    print("\n🎉 All tests passed! Dart service is working correctly.")
    return True

def main():
    """Main function"""
    print("Dart Game Service Integration Test")
    print("=" * 40)
    
    # Start the Dart service
    dart_service_path = "simple_dart_service.dart"
    print(f"Starting Dart service from: {dart_service_path}")
    
    if not dart_subprocess_manager.start_dart_service(dart_service_path):
        print("❌ Failed to start Dart service")
        return 1
    
    # Wait a moment for service to initialize
    time.sleep(2)
    
    # Run tests
    if test_dart_service():
        print("\n✅ Dart service integration successful!")
        return 0
    else:
        print("\n❌ Dart service integration failed!")
        return 1

if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print("\n\nShutting down...")
        dart_subprocess_manager.stop_dart_service()
        sys.exit(0)
    except Exception as e:
        print(f"\nError: {e}")
        dart_subprocess_manager.stop_dart_service()
        sys.exit(1)
