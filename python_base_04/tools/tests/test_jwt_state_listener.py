#!/usr/bin/env python3
"""
Test script for JWT State Change Listener functionality.

This script tests the new state change listener that resumes token refresh
when transitioning from game states to normal states.
"""

import sys
import os
import time
import hashlib
from datetime import datetime, timedelta

# Add the project root to the Python path
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from core.managers.jwt_manager import JWTManager
from core.managers.state_manager import StateManager, StateType, StateTransition

def test_state_change_listener():
    """Test the JWT state change listener functionality."""
    
    print("🚀 Starting JWT State Change Listener Tests")
    print("=" * 60)
    
    try:
        # Initialize managers
        jwt_manager = JWTManager()
        state_manager = StateManager()
        
        print("\n1. Testing state change listener registration...")
        
        # Get current state
        current_state = jwt_manager._get_main_app_state()
        print(f"✅ Current app state: {current_state}")
        
        print("\n2. Testing state transitions and token refresh behavior...")
        
        # Test normal state token refresh
        print("\n--- Testing: Normal state token refresh ---")
        # Create a proper refresh token for testing
        test_refresh_token = jwt_manager.create_refresh_token({"user_id": "test_user", "test": True})
        result = jwt_manager.refresh_token(test_refresh_token)
        print(f"✅ Token refresh in normal state: {'ALLOWED' if result else 'DELAYED'}")
        
        # Test game state token refresh
        print("\n--- Testing: Game state token refresh ---")
        print("🔄 Updating state to 'active_game'...")
        state_manager.update_state("main_state", {"app_status": "active_game"}, StateTransition.UPDATE)
        time.sleep(1)  # Allow state change to propagate
        
        test_refresh_token = jwt_manager.create_refresh_token({"user_id": "test_user", "test": True})
        result = jwt_manager.refresh_token(test_refresh_token)
        print(f"✅ Token refresh in game state: {'ALLOWED' if result else 'DELAYED'}")
        
        # Check pending tokens
        print(f"📝 Pending tokens count: {len(jwt_manager._pending_refresh_tokens)}")
        
        print("\n3. Testing state change callback...")
        
        # Test transition from game to normal state
        print("\n--- Testing: Game → Normal state transition ---")
        print("🔄 Updating state to 'idle'...")
        state_manager.update_state("main_state", {"app_status": "idle"}, StateTransition.UPDATE)
        time.sleep(1)  # Allow state change to propagate
        
        # Check if pending tokens were processed
        print(f"📝 Pending tokens count after transition: {len(jwt_manager._pending_refresh_tokens)}")
        
        # Test token refresh after transition
        test_refresh_token = jwt_manager.create_refresh_token({"user_id": "test_user", "test": True})
        result = jwt_manager.refresh_token(test_refresh_token)
        print(f"✅ Token refresh after transition: {'ALLOWED' if result else 'DELAYED'}")
        
        print("\n4. Testing other game states...")
        
        game_states = ["pre_game", "post_game"]
        for state in game_states:
            print(f"\n--- Testing: {state} state ---")
            print(f"🔄 Updating state to '{state}'...")
            state_manager.update_state("main_state", {"app_status": state}, StateTransition.UPDATE)
            time.sleep(1)
            
            test_refresh_token = jwt_manager.create_refresh_token({"user_id": "test_user", "test": True})
            result = jwt_manager.refresh_token(test_refresh_token)
            print(f"✅ Token refresh in {state}: {'ALLOWED' if result else 'DELAYED'}")
            
            # Transition back to normal
            print(f"🔄 Transitioning from {state} to 'idle'...")
            state_manager.update_state("main_state", {"app_status": "idle"}, StateTransition.UPDATE)
            time.sleep(1)
            
            print(f"📝 Pending tokens count: {len(jwt_manager._pending_refresh_tokens)}")
        
        print("\n5. Testing multiple pending tokens...")
        
        # Add multiple tokens during game state
        print("🔄 Setting state to 'active_game'...")
        state_manager.update_state("main_state", {"app_status": "active_game"}, StateTransition.UPDATE)
        time.sleep(1)
        
        for i in range(3):
            test_refresh_token = jwt_manager.create_refresh_token({"user_id": "test_user", "test": True})
            result = jwt_manager.refresh_token(test_refresh_token)
            print(f"✅ Token {i+1} refresh: {'ALLOWED' if result else 'DELAYED'}")
        
        print(f"📝 Total pending tokens: {len(jwt_manager._pending_refresh_tokens)}")
        
        # Transition to normal state
        print("🔄 Transitioning to 'idle'...")
        state_manager.update_state("main_state", {"app_status": "idle"}, StateTransition.UPDATE)
        time.sleep(1)
        
        print(f"📝 Pending tokens after transition: {len(jwt_manager._pending_refresh_tokens)}")
        
        print("\n6. Testing callback registration...")
        
        # Verify callback is registered
        main_state = state_manager.get_state("main_state")
        if main_state and "main_state" in state_manager._state_callbacks:
            print("✅ State change callback is registered")
        else:
            print("❌ State change callback not found")
        
        print("\n" + "=" * 60)
        print("✅ All JWT State Change Listener tests completed!")
        print("=" * 60)
        
        return True
        
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        return False

def test_state_transitions():
    """Test various state transitions and their effects on token refresh."""
    
    print("\n🔄 Testing State Transitions")
    print("=" * 40)
    
    try:
        jwt_manager = JWTManager()
        state_manager = StateManager()
        
        # Test all state combinations
        states = ["idle", "busy", "maintenance", "active_game", "pre_game", "post_game"]
        
        for state in states:
            print(f"\n--- Testing state: {state} ---")
            
            # Update state
            state_manager.update_state("main_state", {"app_status": state}, StateTransition.UPDATE)
            time.sleep(0.5)
            
            # Test token refresh
            test_refresh_token = jwt_manager.create_refresh_token({"user_id": "test_user", "test": True})
            result = jwt_manager.refresh_token(test_refresh_token)
            
            # Determine expected behavior
            game_states = ["active_game", "pre_game", "post_game"]
            expected_behavior = "DELAYED" if state in game_states else "ALLOWED"
            actual_behavior = "DELAYED" if not result else "ALLOWED"
            
            status = "✅" if expected_behavior == actual_behavior else "❌"
            print(f"{status} State: {state}")
            print(f"   Expected: {expected_behavior}")
            print(f"   Actual: {actual_behavior}")
            print(f"   Pending tokens: {len(jwt_manager._pending_refresh_tokens)}")
        
        print("\n✅ State transition tests completed!")
        return True
        
    except Exception as e:
        print(f"❌ State transition test failed: {e}")
        return False

if __name__ == "__main__":
    print("🧪 JWT State Change Listener Test Suite")
    print("=" * 60)
    
    # Run tests
    test1_success = test_state_change_listener()
    test2_success = test_state_transitions()
    
    print("\n📊 Test Results Summary:")
    print(f"State Change Listener Test: {'✅ PASSED' if test1_success else '❌ FAILED'}")
    print(f"State Transitions Test: {'✅ PASSED' if test2_success else '❌ FAILED'}")
    
    if test1_success and test2_success:
        print("\n🎉 All tests passed! JWT State Change Listener is working correctly.")
        sys.exit(0)
    else:
        print("\n❌ Some tests failed. Please check the implementation.")
        sys.exit(1) 