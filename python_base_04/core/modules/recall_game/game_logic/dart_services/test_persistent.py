#!/usr/bin/env python3
"""
Test script for persistent Dart service
"""

import sys
import os
import time

# Add the python_base_04 directory to the Python path
sys.path.append(os.path.join(os.path.dirname(__file__), '../../../../..'))

from core.modules.recall_game.game_logic.dart_services.dart_subprocess_manager import dart_subprocess_manager

def test_persistent_service():
    """Test the persistent Dart service"""
    print("🧪 Testing Persistent Dart Service")
    print("=" * 40)
    
    # Start the service
    print("1. Starting Dart service...")
    if dart_subprocess_manager.start_dart_service("simple_dart_service.dart"):
        print("   ✅ Dart service started")
    else:
        print("   ❌ Failed to start Dart service")
        return False
    
    # Wait for initialization
    print("2. Waiting for service to initialize...")
    time.sleep(3)
    
    # Test health check
    print("3. Testing health check...")
    if dart_subprocess_manager.health_check():
        print("   ✅ Health check passed")
    else:
        print("   ❌ Health check failed")
        return False
    
    # Test game operations
    print("4. Testing game operations...")
    game_id = "test_persistent_001"
    
    if dart_subprocess_manager.create_game(game_id, max_players=4, min_players=2):
        print("   ✅ Game created")
    else:
        print("   ❌ Failed to create game")
        return False
    
    if dart_subprocess_manager.join_game(game_id, "player_001", "Test Player", "human"):
        print("   ✅ Player joined")
    else:
        print("   ❌ Failed to join player")
        return False
    
    # Test that service is still running
    print("5. Verifying service is still running...")
    if dart_subprocess_manager.health_check():
        print("   ✅ Service is still running")
    else:
        print("   ❌ Service stopped unexpectedly")
        return False
    
    print("\n🎉 All tests passed! Persistent service is working correctly.")
    print("💡 The service is now running and ready for production use.")
    print("🛑 Press Ctrl+C to stop the service when done testing.")
    
    # Keep running until interrupted
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n\n🛑 Stopping service...")
        dart_subprocess_manager.stop_dart_service()
        print("✅ Service stopped")
    
    return True

if __name__ == "__main__":
    test_persistent_service()
