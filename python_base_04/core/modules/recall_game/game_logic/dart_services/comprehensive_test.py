#!/usr/bin/env python3
"""
Comprehensive Test for Python-Dart Integration

This script tests the complete integration between Python and Dart services
for the Recall game, including the subprocess manager and game event coordinator.
"""

import sys
import os
import time
import json

# Add the parent directory to the path
sys.path.append('/Users/sil/Documents/Work/reignofplay/Recall/app_dev/python_base_04')

from dart_subprocess_manager import DartSubprocessManager

def test_dart_subprocess_manager():
    """Test the Dart subprocess manager directly"""
    print("🚀 Testing Dart Subprocess Manager...")
    
    manager = DartSubprocessManager()
    
    # Test 1: Start Dart service
    print("\n📋 Test 1: Starting Dart service")
    if manager.start_dart_service('simple_dart_service.dart'):
        print("✅ Dart service started successfully")
        
        # Test 2: Health check
        print("\n📋 Test 2: Health check")
        if manager.health_check():
            print("✅ Health check passed")
        else:
            print("❌ Health check failed")
            return False
        
        # Test 3: Create game
        print("\n📋 Test 3: Create game")
        game_id = 'test_game_789'
        if manager.create_game(game_id, 4, 2, 'public'):
            print("✅ Game created successfully")
        else:
            print("❌ Game creation failed")
            return False
        
        # Test 4: Add player
        print("\n📋 Test 4: Add player")
        player_data = {
            'player_id': 'player1',
            'player_name': 'Alice',
            'player_type': 'human'
        }
        if manager.add_player(game_id, player_data):
            print("✅ Player added successfully")
        else:
            print("❌ Failed to add player")
            return False
        
        # Test 5: Start game
        print("\n📋 Test 5: Start game")
        if manager.start_game(game_id):
            print("✅ Game started successfully")
        else:
            print("❌ Game start failed")
            return False
        
        # Test 6: Player action
        print("\n📋 Test 6: Player action")
        action_data = {
            'action': 'draw_from_deck',
            'player_id': 'player1'
        }
        if manager.player_action(game_id, 'test_session', 'draw_from_deck', action_data):
            print("✅ Player action successful")
        else:
            print("❌ Player action failed")
            return False
        
        # Test 7: Get game state
        print("\n📋 Test 7: Get game state")
        game_state = manager.get_game_state(game_id)
        if game_state:
            print("✅ Game state retrieved successfully")
            print(f"   Status: {game_state.get('status', 'unknown')}")
            print(f"   Message: {game_state.get('message', 'unknown')}")
        else:
            print("❌ Failed to get game state")
            return False
        
        print("\n🛑 Stopping Dart service...")
        manager.stop_dart_service()
        print("✅ Dart subprocess manager tests completed successfully!")
        return True
        
    else:
        print("❌ Failed to start Dart service")
        return False

def test_dart_service_directly():
    """Test the Dart service directly via subprocess"""
    print("\n🚀 Testing Dart Service Directly...")
    
    import subprocess
    
    try:
        # Start the Dart service
        process = subprocess.Popen(
            ['dart', 'run', 'simple_dart_service.dart'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=os.getcwd()
        )
        
        # Test health check
        health_check = {
            'action': 'health_check',
            'game_id': '',
            'data': {}
        }
        
        process.stdin.write(json.dumps(health_check) + '\n')
        process.stdin.flush()
        
        # Read response
        response_line = process.stdout.readline()
        if response_line and response_line.strip():
            response = json.loads(response_line.strip())
            print(f"✅ Direct Dart service response: {response}")
            
            if response.get('status') == 'healthy':
                print("✅ Direct Dart service test passed")
                process.terminate()
                return True
            else:
                print("❌ Direct Dart service returned error")
                process.terminate()
                return False
        else:
            print("❌ No response from direct Dart service")
            process.terminate()
            return False
            
    except Exception as e:
        print(f"❌ Error testing direct Dart service: {e}")
        return False

def main():
    """Run all tests"""
    print("=" * 60)
    print("🧪 COMPREHENSIVE PYTHON-DART INTEGRATION TEST")
    print("=" * 60)
    
    # Change to the correct directory
    os.chdir('/Users/sil/Documents/Work/reignofplay/Recall/app_dev/python_base_04/core/modules/recall_game/game_logic/dart_services')
    
    # Test 1: Direct Dart service
    direct_test_passed = test_dart_service_directly()
    
    # Test 2: Python subprocess manager
    manager_test_passed = test_dart_subprocess_manager()
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)
    print(f"Direct Dart Service Test: {'✅ PASSED' if direct_test_passed else '❌ FAILED'}")
    print(f"Python Subprocess Manager Test: {'✅ PASSED' if manager_test_passed else '❌ FAILED'}")
    
    if direct_test_passed and manager_test_passed:
        print("\n🎉 ALL TESTS PASSED! Python-Dart integration is working correctly.")
        return True
    else:
        print("\n💥 SOME TESTS FAILED! Check the output above for details.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
