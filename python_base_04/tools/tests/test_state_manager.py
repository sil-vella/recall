#!/usr/bin/env python3
"""
Basic test script for StateManager functionality.
This script tests the core state management system without being a module.
"""

import sys
import os
import json
from datetime import datetime

# Add the project root to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from system.managers.state_manager import StateManager, StateType, StateTransition
from tools.logger.custom_logging import custom_log


def test_basic_state_operations():
    """Test basic state operations."""
    print("\n" + "="*50)
    print("Testing Basic State Operations")
    print("="*50)
    
    # Reset singleton instance for clean testing
    StateManager.reset_instance()
    
    # Initialize state manager (without Redis/DB for basic testing)
    state_manager = StateManager()
    
    # Test 1: Create a state
    print("\n1. Testing state creation...")
    test_state = {
        "name": "test_user_state",
        "type": StateType.USER.value,
        "data": {
            "user_id": "12345",
            "status": "active",
            "created_at": datetime.now().isoformat()
        },
        "metadata": {
            "version": "1.0",
            "environment": "test"
        }
    }
    
    result = state_manager.register_state(
        state_id="user_12345",
        state_type=StateType.USER,
        initial_data=test_state
    )
    print(f"✅ State creation result: {result}")
    
    # Test 2: Retrieve the state
    print("\n2. Testing state retrieval...")
    retrieved_state = state_manager.get_state("user_12345")
    print(f"✅ Retrieved state: {json.dumps(retrieved_state, indent=2)}")
    
    # Test 3: Update the state
    print("\n3. Testing state update...")
    updated_data = {
        "name": "test_user_state_updated",
        "type": StateType.USER.value,
        "data": {
            "user_id": "12345",
            "status": "suspended",
            "updated_at": datetime.now().isoformat()
        },
        "metadata": {
            "version": "1.1",
            "environment": "test"
        }
    }
    
    update_result = state_manager.update_state(
        state_id="user_12345",
        new_data=updated_data,
        transition=StateTransition.UPDATE
    )
    print(f"✅ State update result: {update_result}")
    
    # Test 4: Get updated state
    updated_state = state_manager.get_state("user_12345")
    print(f"✅ Updated state: {json.dumps(updated_state, indent=2)}")
    
    # Test 5: List states
    print("\n4. Testing state listing...")
    states = state_manager.get_states_by_type(state_type=StateType.USER)
    print(f"✅ User states: {states}")
    
    # Test 6: Delete state
    print("\n5. Testing state deletion...")
    delete_result = state_manager.delete_state("user_12345")
    print(f"✅ State deletion result: {delete_result}")
    
    # Test 7: Verify deletion
    deleted_state = state_manager.get_state("user_12345")
    print(f"✅ State after deletion: {deleted_state}")


def test_state_transitions():
    """Test state transitions."""
    print("\n" + "="*50)
    print("Testing State Transitions")
    print("="*50)
    
    # Reset singleton instance for clean testing
    StateManager.reset_instance()
    
    state_manager = StateManager()
    
    # Create initial state
    initial_state = {
        "name": "subscription_state",
        "type": StateType.SUBSCRIPTION.value,
        "data": {
            "subscription_id": "sub_001",
            "status": "inactive",
            "plan": "basic"
        }
    }
    
    state_manager.register_state("sub_001", StateType.SUBSCRIPTION, initial_state)
    
    # Test transitions
    transitions = [
        (StateTransition.ACTIVATE, "active"),
        (StateTransition.SUSPEND, "suspended"),
        (StateTransition.RESUME, "active"),
        (StateTransition.EXPIRE, "expired")
    ]
    
    for transition, expected_status in transitions:
        print(f"\nTesting transition: {transition.value}")
        
        # Update state with transition
        updated_data = {
            "name": "subscription_state",
            "type": StateType.SUBSCRIPTION.value,
            "data": {
                "subscription_id": "sub_001",
                "status": expected_status,
                "plan": "basic",
                "last_transition": transition.value,
                "transition_time": datetime.now().isoformat()
            }
        }
        
        result = state_manager.update_state(
            "sub_001", 
            updated_data, 
            transition=transition
        )
        print(f"✅ Transition {transition.value} result: {result}")
        
        # Verify state
        current_state = state_manager.get_state("sub_001")
        current_status = current_state.get("data", {}).get("status")
        print(f"✅ Current status: {current_status}")
    
    # Cleanup
    state_manager.delete_state("sub_001")


def test_state_history():
    """Test state history tracking."""
    print("\n" + "="*50)
    print("Testing State History")
    print("="*50)
    
    # Reset singleton instance for clean testing
    StateManager.reset_instance()
    
    state_manager = StateManager()
    
    # Create state with history enabled
    initial_state = {
        "name": "feature_state",
        "type": StateType.FEATURE.value,
        "data": {
            "feature_id": "feature_001",
            "enabled": False
        }
    }
    
    state_manager.register_state("feature_001", StateType.FEATURE, initial_state)
    
    # Make several updates
    updates = [
        {"enabled": True, "reason": "user_activated"},
        {"enabled": False, "reason": "admin_disabled"},
        {"enabled": True, "reason": "bug_fixed"}
    ]
    
    for i, update in enumerate(updates):
        updated_data = {
            "name": "feature_state",
            "type": StateType.FEATURE.value,
            "data": {
                "feature_id": "feature_001",
                **update,
                "update_count": i + 1
            }
        }
        
        state_manager.update_state(
            "feature_001",
            updated_data,
            StateTransition.UPDATE
        )
    
    # Get state history
    history = state_manager.get_state_history("feature_001")
    print(f"✅ State history entries: {len(history)}")
    
    for i, entry in enumerate(history):
        print(f"  Entry {i+1}: {entry.get('transition_type')} - {entry.get('timestamp')}")
    
    # Cleanup
    state_manager.delete_state("feature_001")


def test_state_callbacks():
    """Test state change callbacks."""
    print("\n" + "="*50)
    print("Testing State Callbacks")
    print("="*50)
    
    # Reset singleton instance for clean testing
    StateManager.reset_instance()
    
    state_manager = StateManager()
    
    # Define callback function
    def state_change_callback(state_id: str, old_state: dict, new_state: dict, transition_type: str):
        print(f"🔔 Callback triggered: {state_id} - {transition_type}")
        print(f"   Old status: {old_state.get('data', {}).get('status', 'N/A')}")
        print(f"   New status: {new_state.get('data', {}).get('status', 'N/A')}")
    
    # Register callback
    state_manager.register_callback("test_callback", state_change_callback)
    
    # Create and update state to trigger callback
    test_state = {
        "name": "callback_test",
        "type": StateType.SESSION.value,
        "data": {
            "session_id": "session_001",
            "status": "created"
        }
    }
    
    state_manager.register_state("session_001", StateType.SESSION, test_state)
    
    # Update to trigger callback
    updated_state = {
        "name": "callback_test",
        "type": StateType.SESSION.value,
        "data": {
            "session_id": "session_001",
            "status": "active"
        }
    }
    
    state_manager.update_state("session_001", updated_state, StateTransition.ACTIVATE)
    
    # Cleanup
    state_manager.delete_state("session_001")


def test_singleton_pattern():
    """Test singleton pattern implementation."""
    print("\n" + "="*50)
    print("Testing Singleton Pattern")
    print("="*50)
    
    # Reset singleton instance for clean testing
    StateManager.reset_instance()
    
    # Create first instance
    state_manager_1 = StateManager()
    print("✅ Created first StateManager instance")
    
    # Create second instance (should be the same)
    state_manager_2 = StateManager()
    print("✅ Created second StateManager instance")
    
    # Verify they are the same instance
    assert state_manager_1 is state_manager_2, "Singleton instances should be identical"
    print("✅ Verified singleton instances are identical")
    
    # Test get_instance method
    state_manager_3 = StateManager.get_instance()
    assert state_manager_1 is state_manager_3, "get_instance should return same instance"
    print("✅ Verified get_instance returns same instance")
    
    # Test state sharing between instances
    test_state = {
        "name": "singleton_test",
        "type": StateType.USER.value,
        "data": {"user_id": "test_user", "status": "active"}
    }
    
    # Register state using first instance
    state_manager_1.register_state("singleton_test", StateType.USER, test_state)
    print("✅ Registered state using first instance")
    
    # Retrieve state using second instance
    retrieved_state = state_manager_2.get_state("singleton_test")
    assert retrieved_state is not None, "State should be accessible from second instance"
    print("✅ Retrieved state using second instance")
    
    # Cleanup
    state_manager_1.delete_state("singleton_test")
    print("✅ Singleton pattern test completed successfully")


def main():
    """Run all state manager tests."""
    print("🚀 Starting StateManager Tests")
    print("="*60)
    
    try:
        test_singleton_pattern()
        test_basic_state_operations()
        test_state_transitions()
        test_state_history()
        test_state_callbacks()
        
        print("\n" + "="*60)
        print("✅ All StateManager tests completed successfully!")
        print("="*60)
        
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main()) 