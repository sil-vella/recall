#!/usr/bin/env python3
"""
Utility script to update the main app state for testing state-dependent JWT TTL.
"""

import sys
import os
import json
from datetime import datetime

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core.managers.state_manager import StateManager, StateTransition
def update_app_state(new_state: str):
    """Update the main app state."""
    try:
        state_manager = StateManager()
        
        # Get current state
        current_state = state_manager.get_state("main_state")
        
        if not current_state:
            print("❌ Main state not found. Please ensure StateManager is initialized.")
            return False
        
        # Update state data
        new_data = current_state["data"].copy()
        new_data["app_status"] = new_state
        new_data["last_updated"] = datetime.utcnow().isoformat()
        
        # Update state
        success = state_manager.update_state(
            "main_state",
            new_data,
            StateTransition.UPDATE
        )
        
        if success:
            print(f"✅ Successfully updated app state to: {new_state}")
            
            # Show current state
            updated_state = state_manager.get_state("main_state")
            if updated_state:
                print(f"📊 Current app status: {updated_state['data']['app_status']}")
                print(f"🕒 Last updated: {updated_state['data']['last_updated']}")
            
            return True
        else:
            print(f"❌ Failed to update app state to: {new_state}")
            return False
            
    except Exception as e:
        print(f"❌ Error updating app state: {e}")
        return False


def show_current_state():
    """Show the current main app state."""
    try:
        state_manager = StateManager()
        current_state = state_manager.get_state("main_state")
        
        if current_state:
            print("📊 Current Main App State:")
            print(f"   Status: {current_state['data']['app_status']}")
            print(f"   Version: {current_state['data']['version']}")
            print(f"   Environment: {current_state['data']['environment']}")
            print(f"   Last Updated: {current_state['data'].get('last_updated', 'N/A')}")
            
            # Show metrics
            metrics = current_state['data'].get('metrics', {})
            print(f"   Active Users: {metrics.get('active_users', 0)}")
            print(f"   Active Sessions: {metrics.get('active_sessions', 0)}")
            print(f"   Total Requests: {metrics.get('total_requests', 0)}")
        else:
            print("❌ Main app state not found")
            
    except Exception as e:
        print(f"❌ Error showing current state: {e}")


def main():
    """Main function."""
    if len(sys.argv) < 2:
        print("Usage: python update_app_state.py <new_state>")
        print("Available states: idle, active_game, pre_game, post_game, busy, maintenance")
        print("\nExamples:")
        print("  python update_app_state.py idle")
        print("  python update_app_state.py active_game")
        print("  python update_app_state.py show")
        return
    
    command = sys.argv[1].lower()
    
    if command == "show":
        show_current_state()
    elif command in ["idle", "active_game", "pre_game", "post_game", "busy", "maintenance"]:
        update_app_state(command)
    else:
        print(f"❌ Invalid state: {command}")
        print("Available states: idle, active_game, pre_game, post_game, busy, maintenance")


if __name__ == "__main__":
    main() 