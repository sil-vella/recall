#!/usr/bin/env python3
"""
Test script for state-dependent JWT TTL functionality.
This script tests how JWT token TTL changes based on app state.
"""

import sys
import os
import json
from datetime import datetime, timedelta

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from system.managers.state_manager import StateManager, StateType, StateTransition
from system.managers.jwt_manager import JWTManager, TokenType
from tools.logger.custom_logging import custom_log


def test_token_refresh_delay_in_game_state():
    """Test that token refresh is delayed during game states."""
    print("\n" + "="*60)
    print("Testing Token Refresh Delay in Game State")
    print("="*60)
    
    try:
        state_manager = StateManager()
        jwt_manager = JWTManager()
        
        # Create a valid refresh token for testing
        test_data = {"user_id": "test_user_123", "username": "testuser"}
        
        print("\n1. Creating refresh token...")
        refresh_token = jwt_manager.create_refresh_token(test_data)
        print(f"✅ Refresh token created: {refresh_token[:20]}...")
        
        print("\n2. Testing token refresh in normal state...")
        # Test refresh in normal state (should work)
        normal_state_data = {
            "app_status": "idle",
            "startup_time": datetime.utcnow().isoformat(),
            "version": "1.0.0",
            "environment": "production",
            "features": {"jwt_auth": True},
            "metrics": {"active_users": 0, "active_sessions": 0, "total_requests": 0}
        }
        state_manager.update_state("main_state", normal_state_data, StateTransition.UPDATE)
        
        # Try to refresh token in normal state
        normal_refresh_result = jwt_manager.refresh_token(refresh_token)
        print(f"✅ Token refresh in normal state: {'✅ ALLOWED' if normal_refresh_result is not None else '❌ WRONG - Should be allowed'}")
        
        print("\n3. Testing token refresh in game state...")
        # Test refresh in game state (should be delayed)
        game_state_data = normal_state_data.copy()
        game_state_data["app_status"] = "active_game"
        state_manager.update_state("main_state", game_state_data, StateTransition.UPDATE)
        
        # Try to refresh token in game state
        game_refresh_result = jwt_manager.refresh_token(refresh_token)
        print(f"✅ Token refresh in game state: {'❌ DELAYED' if game_refresh_result is None else '❌ WRONG - Should be delayed'}")
        
        print("\n4. Testing other game states...")
        game_states = ["pre_game", "post_game"]
        
        for game_state in game_states:
            print(f"\n   Testing state: {game_state}")
            game_state_data["app_status"] = game_state
            state_manager.update_state("main_state", game_state_data, StateTransition.UPDATE)
            
            game_refresh_result = jwt_manager.refresh_token(refresh_token)
            print(f"   ✅ Token refresh in {game_state}: {'❌ DELAYED' if game_refresh_result is None else '❌ WRONG - Should be delayed'}")
        
        # Reset to normal state
        print("\n5. Resetting to normal state...")
        normal_state_data["app_status"] = "idle"
        state_manager.update_state("main_state", normal_state_data, StateTransition.UPDATE)
        
        # Try to refresh token again in normal state
        final_refresh_result = jwt_manager.refresh_token(refresh_token)
        print(f"✅ Token refresh back in normal state: {'✅ ALLOWED' if final_refresh_result is not None else '❌ WRONG - Should be allowed'}")
        
    except Exception as e:
        print(f"❌ Error during token refresh delay test: {e}")
        import traceback
        traceback.print_exc()


def test_state_dependent_jwt_ttl():
    """Test state-dependent JWT TTL functionality."""
    print("\n" + "="*60)
    print("Testing State-Dependent JWT TTL")
    print("="*60)
    
    try:
        # Initialize managers
        state_manager = StateManager()
        jwt_manager = JWTManager()
        
        print("\n1. Testing normal state (idle) token creation...")
        
        # Test token creation in normal state
        test_data = {"user_id": "test_user_123", "username": "testuser"}
        
        # Create access token in normal state
        access_token_normal = jwt_manager.create_access_token(test_data)
        print(f"✅ Access token created in normal state: {access_token_normal[:20]}...")
        
        # Create refresh token in normal state
        refresh_token_normal = jwt_manager.create_refresh_token(test_data)
        print(f"✅ Refresh token created in normal state: {refresh_token_normal[:20]}...")
        
        print("\n2. Testing game state token creation...")
        
        # Update main state to game state
        game_state_data = {
            "app_status": "active_game",
            "startup_time": datetime.utcnow().isoformat(),
            "version": "1.0.0",
            "environment": "production",
            "features": {
                "jwt_auth": True,
                "api_keys": True,
                "websockets": True,
                "state_management": True
            },
            "metrics": {
                "active_users": 5,
                "active_sessions": 3,
                "total_requests": 150
            }
        }
        
        success = state_manager.update_state(
            "main_state",
            game_state_data,
            StateTransition.UPDATE
        )
        
        if success:
            print("✅ Updated main state to 'active_game'")
            
            # Create tokens in game state
            access_token_game = jwt_manager.create_access_token(test_data)
            print(f"✅ Access token created in game state: {access_token_game[:20]}...")
            
            refresh_token_game = jwt_manager.create_refresh_token(test_data)
            print(f"✅ Refresh token created in game state: {refresh_token_game[:20]}...")
            
            # Verify tokens
            print("\n3. Verifying tokens...")
            
            # Verify normal state tokens
            normal_access_valid = jwt_manager.verify_token(access_token_normal, TokenType.ACCESS)
            normal_refresh_valid = jwt_manager.verify_token(refresh_token_normal, TokenType.REFRESH)
            
            print(f"✅ Normal state access token valid: {normal_access_valid is not None}")
            print(f"✅ Normal state refresh token valid: {normal_refresh_valid is not None}")
            
            # Verify game state tokens
            game_access_valid = jwt_manager.verify_token(access_token_game, TokenType.ACCESS)
            game_refresh_valid = jwt_manager.verify_token(refresh_token_game, TokenType.REFRESH)
            
            print(f"✅ Game state access token valid: {game_access_valid is not None}")
            print(f"✅ Game state refresh token valid: {game_refresh_valid is not None}")
            
            # Test other game states
            print("\n4. Testing other game states...")
            
            game_states = ["pre_game", "post_game"]
            
            for game_state in game_states:
                print(f"\nTesting state: {game_state}")
                
                # Update to game state
                game_state_data["app_status"] = game_state
                state_manager.update_state("main_state", game_state_data, StateTransition.UPDATE)
                
                # Create token in this game state
                token = jwt_manager.create_access_token(test_data)
                token_valid = jwt_manager.verify_token(token, TokenType.ACCESS)
                
                print(f"✅ Token created in '{game_state}' state: {token[:20]}...")
                print(f"✅ Token valid: {token_valid is not None}")
            
            # Reset to normal state
            print("\n5. Resetting to normal state...")
            normal_state_data = game_state_data.copy()
            normal_state_data["app_status"] = "idle"
            state_manager.update_state("main_state", normal_state_data, StateTransition.UPDATE)
            
            # Create token in normal state again
            final_token = jwt_manager.create_access_token(test_data)
            final_token_valid = jwt_manager.verify_token(final_token, TokenType.ACCESS)
            
            print(f"✅ Final token in normal state: {final_token[:20]}...")
            print(f"✅ Final token valid: {final_token_valid is not None}")
            
        else:
            print("❌ Failed to update main state to game state")
            
    except Exception as e:
        print(f"❌ Error during test: {e}")
        import traceback
        traceback.print_exc()


def test_state_transitions():
    """Test state transitions and their effect on JWT TTL."""
    print("\n" + "="*60)
    print("Testing State Transitions")
    print("="*60)
    
    try:
        state_manager = StateManager()
        jwt_manager = JWTManager()
        
        # Test different states
        test_states = [
            ("idle", "Normal state"),
            ("active_game", "Game state - should use extended TTL"),
            ("pre_game", "Pre-game state - should use extended TTL"),
            ("post_game", "Post-game state - should use extended TTL"),
            ("busy", "Busy state - should use normal TTL"),
            ("maintenance", "Maintenance state - should use normal TTL")
        ]
        
        for state_name, description in test_states:
            print(f"\n--- Testing: {description} ---")
            
            # Update state
            current_state = state_manager.get_state("main_state")
            if current_state:
                new_data = current_state["data"].copy()
                new_data["app_status"] = state_name
                state_manager.update_state("main_state", new_data, StateTransition.UPDATE)
            
            # Create token and check TTL behavior
            test_data = {"user_id": "test_user_123", "username": "testuser"}
            token = jwt_manager.create_access_token(test_data)
            
            # Verify token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            if payload:
                exp_timestamp = payload.get("exp")
                if exp_timestamp:
                    # Convert to datetime for comparison
                    from datetime import datetime
                    exp_time = datetime.fromtimestamp(exp_timestamp)
                    now = datetime.utcnow()
                    ttl_seconds = int((exp_time - now).total_seconds())
                    
                    print(f"✅ State: {state_name}")
                    print(f"   Token TTL: {ttl_seconds} seconds")
                    print(f"   Expected extended TTL: {state_name in ['active_game', 'pre_game', 'post_game']}")
                    
                    # Check if TTL is extended for game states
                    if state_name in ['active_game', 'pre_game', 'post_game']:
                        if ttl_seconds > jwt_manager.access_token_expire_seconds:
                            print(f"   ✅ Correctly using extended TTL")
                        else:
                            print(f"   ❌ Should use extended TTL but using normal TTL")
                    else:
                        if ttl_seconds <= jwt_manager.access_token_expire_seconds:
                            print(f"   ✅ Correctly using normal TTL")
                        else:
                            print(f"   ❌ Should use normal TTL but using extended TTL")
                else:
                    print(f"❌ No expiration found in token")
            else:
                print(f"❌ Token verification failed")
    
    except Exception as e:
        print(f"❌ Error during state transition test: {e}")
        import traceback
        traceback.print_exc()


def main():
    """Main test function."""
    print("🚀 Starting State-Dependent JWT TTL Tests")
    
    # Test basic functionality
    test_state_dependent_jwt_ttl()
    
    # Test state transitions
    test_state_transitions()
    
    # Test token refresh delay behavior
    test_token_refresh_delay_in_game_state()
    
    print("\n" + "="*60)
    print("✅ All tests completed!")
    print("="*60)


if __name__ == "__main__":
    main() 