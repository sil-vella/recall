from typing import Dict, Any, Optional, List, Callable
from datetime import datetime
from enum import Enum
import logging
from core.managers.redis_manager import RedisManager
from core.managers.database_manager import DatabaseManager


class StateType(Enum):
    """Core state types that can be managed"""
    SYSTEM = "system"
    USER = "user"
    SESSION = "session"
    RESOURCE = "resource"
    FEATURE = "feature"
    SUBSCRIPTION = "subscription"


class StateTransition(Enum):
    """Core state transition types"""
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"
    ACTIVATE = "activate"
    DEACTIVATE = "deactivate"
    SUSPEND = "suspend"
    RESUME = "resume"
    EXPIRE = "expire"
    RENEW = "renew"


class StateManager:
    """
    Core State Management System - Central orchestrator for all application states.
    
    This is a generic, business-logic-agnostic state management system that provides:
    - State storage and retrieval
    - State transitions with validation
    - State change notifications
    - State history tracking
    - State-based access control
    
    Singleton Pattern: Only one instance exists throughout the application lifecycle.
    """
    
    _instance = None
    _initialized = False
    
    def __new__(cls, redis_manager: Optional[RedisManager] = None, 
                database_manager: Optional[DatabaseManager] = None):
        """Singleton pattern implementation - ensures only one instance exists."""
        if cls._instance is None:
            cls._instance = super(StateManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self, redis_manager: Optional[RedisManager] = None, 
                 database_manager: Optional[DatabaseManager] = None):
        """Initialize the state manager with optional external managers (singleton)."""
        # Prevent re-initialization if already initialized
        if StateManager._initialized:
            return
            
        self.logger = logging.getLogger(__name__)
        
        # Use provided managers or create new ones
        self.redis_manager = redis_manager if redis_manager else RedisManager()
        self.database_manager = database_manager if database_manager else DatabaseManager()
        
        # State storage
        self._states: Dict[str, Dict[str, Any]] = {}
        self._state_history: Dict[str, List[Dict[str, Any]]] = {}
        self._transition_rules: Dict[str, Dict[str, List[str]]] = {}
        self._state_callbacks: Dict[str, List[Callable]] = {}
        
        # Configuration
        self.state_ttl = 3600  # 1 hour default TTL
        self.history_limit = 100  # Max history entries per state
        self.enable_notifications = True
        
        # Mark as initialized
        StateManager._initialized = True
        
        # Initialize main app state
        self._initialize_main_app_state()
        
        @classmethod
    def get_instance(cls, redis_manager: Optional[RedisManager] = None, 
                    database_manager: Optional[DatabaseManager] = None) -> 'StateManager':
        """
        Get the singleton instance of StateManager.
        
        Args:
            redis_manager: Optional Redis manager instance
            database_manager: Optional database manager instance
            
        Returns:
            StateManager: The singleton instance
        """
        return cls(redis_manager, database_manager)
    
    @classmethod
    def reset_instance(cls):
        """Reset the singleton instance (useful for testing)."""
        cls._instance = None
        cls._initialized = False

    def register_state(self, state_id: str, state_type: StateType, 
                      initial_data: Dict[str, Any], 
                      allowed_transitions: Optional[List[str]] = None) -> bool:
        """
        Register a new state in the system.
        
        Args:
            state_id: Unique identifier for the state
            state_type: Type of state (system, user, session, etc.)
            initial_data: Initial state data
            allowed_transitions: List of allowed transition types
            
        Returns:
            bool: True if registration successful
        """
        try:
            if state_id in self._states:
                self.logger.warning(f"State {state_id} already exists, updating instead")
                return self.update_state(state_id, initial_data)
            
            # Create state record
            state_record = {
                'id': state_id,
                'type': state_type.value,
                'data': initial_data,
                'created_at': datetime.utcnow().isoformat(),
                'updated_at': datetime.utcnow().isoformat(),
                'version': 1,
                'active': True
            }
            
            # Store in memory
            self._states[state_id] = state_record
            
            # Store in Redis for persistence
            self._store_state_in_redis(state_id, state_record)
            
            # Store in database for long-term persistence
            self._store_state_in_database(state_id, state_record)
            
            # Initialize history
            self._state_history[state_id] = []
            self._add_to_history(state_id, StateTransition.CREATE.value, initial_data)
            
            # Set transition rules
            if allowed_transitions:
                self._transition_rules[state_id] = {
                    'allowed': allowed_transitions,
                    'current': StateTransition.CREATE.value
                }
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to register state {state_id}: {e}")
            return False

    def get_state(self, state_id: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve a state by ID.
        
        Args:
            state_id: State identifier
            
        Returns:
            Dict containing state data or None if not found
        """
        try:
            # Try memory first
            if state_id in self._states:
                return self._states[state_id]
            
            # Try Redis
            redis_state = self._get_state_from_redis(state_id)
            if redis_state:
                self._states[state_id] = redis_state
                return redis_state
            
            # Try database
            db_state = self._get_state_from_database(state_id)
            if db_state:
                self._states[state_id] = db_state
                # Cache in Redis
                self._store_state_in_redis(state_id, db_state)
                return db_state
            
            return None
            
        except Exception as e:
            self.logger.error(f"Failed to get state {state_id}: {e}")
            return None

    def update_state(self, state_id: str, new_data: Dict[str, Any], 
                    transition: Optional[StateTransition] = None) -> bool:
        """
        Update an existing state.
        
        Args:
            state_id: State identifier
            new_data: New state data
            transition: Optional transition type
            
        Returns:
            bool: True if update successful
        """
        try:
            current_state = self.get_state(state_id)
            if not current_state:
                self.logger.error(f"State {state_id} not found for update")
                return False
            
            # Validate transition if provided
            if transition and not self._validate_transition(state_id, transition):
                self.logger.error(f"Invalid transition {transition.value} for state {state_id}")
                return False
            
            # Update state data
            updated_state = current_state.copy()
            updated_state['data'].update(new_data)
            updated_state['updated_at'] = datetime.utcnow().isoformat()
            updated_state['version'] += 1
            
            # Store updated state
            self._states[state_id] = updated_state
            self._store_state_in_redis(state_id, updated_state)
            self._store_state_in_database(state_id, updated_state)
            
            # Add to history
            transition_type = transition.value if transition else StateTransition.UPDATE.value
            self._add_to_history(state_id, transition_type, new_data)
            
            # Update transition rules
            if transition:
                self._update_transition_rules(state_id, transition)
            
            # Trigger callbacks
            self._trigger_state_callbacks(state_id, transition_type, new_data)
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to update state {state_id}: {e}")
            return False

    def delete_state(self, state_id: str) -> bool:
        """
        Delete a state from the system.
        
        Args:
            state_id: State identifier
            
        Returns:
            bool: True if deletion successful
        """
        try:
            if state_id not in self._states:
                self.logger.warning(f"State {state_id} not found for deletion")
                return False
            
            # Add deletion to history before removing
            self._add_to_history(state_id, StateTransition.DELETE.value, {})
            
            # Remove from memory
            del self._states[state_id]
            
            # Remove from Redis
            self._remove_state_from_redis(state_id)
            
            # Mark as deleted in database (soft delete)
            self._mark_state_deleted_in_database(state_id)
            
            # Clean up related data
            if state_id in self._state_history:
                del self._state_history[state_id]
            if state_id in self._transition_rules:
                del self._transition_rules[state_id]
            if state_id in self._state_callbacks:
                del self._state_callbacks[state_id]
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to delete state {state_id}: {e}")
            return False

    def get_state_history(self, state_id: str, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get history of state changes.
        
        Args:
            state_id: State identifier
            limit: Maximum number of history entries to return
            
        Returns:
            List of history entries
        """
        try:
            history = self._state_history.get(state_id, [])
            if limit:
                history = history[-limit:]
            return history
            
        except Exception as e:
            self.logger.error(f"Failed to get history for state {state_id}: {e}")
            return []

    def register_callback(self, state_id: str, callback: Callable) -> bool:
        """
        Register a callback function to be called when state changes.
        
        Args:
            state_id: State identifier
            callback: Function to call on state change
            
        Returns:
            bool: True if registration successful
        """
        try:
            if state_id not in self._state_callbacks:
                self._state_callbacks[state_id] = []
            
            self._state_callbacks[state_id].append(callback)
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to register callback for state {state_id}: {e}")
            return False

    def get_states_by_type(self, state_type: StateType) -> List[Dict[str, Any]]:
        """
        Get all states of a specific type.
        
        Args:
            state_type: Type of states to retrieve
            
        Returns:
            List of states of the specified type
        """
        try:
            states = []
            for state_id, state_data in self._states.items():
                if state_data.get('type') == state_type.value:
                    states.append(state_data)
            return states
            
        except Exception as e:
            self.logger.error(f"Failed to get states by type {state_type.value}: {e}")
            return []

    def get_active_states(self) -> List[Dict[str, Any]]:
        """
        Get all active states.
        
        Returns:
            List of active states
        """
        try:
            return [state for state in self._states.values() if state.get('active', True)]
        except Exception as e:
            self.logger.error(f"Failed to get active states: {e}")
            return []

    # Private helper methods

    def _validate_transition(self, state_id: str, transition: StateTransition) -> bool:
        """Validate if a transition is allowed for a state."""
        if state_id not in self._transition_rules:
            return True  # No rules means all transitions allowed
        
        allowed_transitions = self._transition_rules[state_id].get('allowed', [])
        return transition.value in allowed_transitions

    def _update_transition_rules(self, state_id: str, transition: StateTransition):
        """Update transition rules after a state change."""
        if state_id in self._transition_rules:
            self._transition_rules[state_id]['current'] = transition.value

    def _add_to_history(self, state_id: str, transition: str, data: Dict[str, Any]):
        """Add an entry to state history."""
        if state_id not in self._state_history:
            self._state_history[state_id] = []
        
        history_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'transition': transition,
            'data': data,
            'version': self._states.get(state_id, {}).get('version', 1)
        }
        
        self._state_history[state_id].append(history_entry)
        
        # Limit history size
        if len(self._state_history[state_id]) > self.history_limit:
            self._state_history[state_id] = self._state_history[state_id][-self.history_limit:]

    def _trigger_state_callbacks(self, state_id: str, transition: str, data: Dict[str, Any]):
        """Trigger registered callbacks for state changes."""
        if not self.enable_notifications or state_id not in self._state_callbacks:
            return
        
        for callback in self._state_callbacks[state_id]:
            try:
                callback(state_id, transition, data)
            except Exception as e:
                self.logger.error(f"Callback error for state {state_id}: {e}")

    def _store_state_in_redis(self, state_id: str, state_data: Dict[str, Any]):
        """Store state in Redis cache."""
        try:
            self.redis_manager.set(f"state:{state_id}", state_data, expire=self.state_ttl)
        except Exception as e:
            self.logger.warning(f"Failed to store state {state_id} in Redis: {e}")

    def _get_state_from_redis(self, state_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve state from Redis cache."""
        try:
            return self.redis_manager.get(f"state:{state_id}")
        except Exception as e:
            self.logger.warning(f"Failed to get state {state_id} from Redis: {e}")
            return None

    def _remove_state_from_redis(self, state_id: str):
        """Remove state from Redis cache."""
        try:
            self.redis_manager.delete(f"state:{state_id}")
        except Exception as e:
            self.logger.warning(f"Failed to remove state {state_id} from Redis: {e}")

    def _store_state_in_database(self, state_id: str, state_data: Dict[str, Any]):
        """Store state in database for persistence."""
        try:
            if self.database_manager.available:
                self.database_manager.insert("states", state_data)
        except Exception as e:
            self.logger.warning(f"Failed to store state {state_id} in database: {e}")

    def _get_state_from_database(self, state_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve state from database."""
        try:
            if self.database_manager.available:
                return self.database_manager.find_one("states", {"id": state_id})
        except Exception as e:
            self.logger.warning(f"Failed to get state {state_id} from database: {e}")
        return None

    def _mark_state_deleted_in_database(self, state_id: str):
        """Mark state as deleted in database (soft delete)."""
        try:
            if self.database_manager.available:
                self.database_manager.update(
                    "states", 
                    {"id": state_id}, 
                    {"active": False, "deleted_at": datetime.utcnow().isoformat()}
                )
        except Exception as e:
            self.logger.warning(f"Failed to mark state {state_id} as deleted in database: {e}")

    def _initialize_main_app_state(self):
        """Initialize the main application state."""
        try:
            # Check if main state already exists
            existing_state = self.get_state("main_state")
            if existing_state:
                return
            
            # Create main app state
            main_state_data = {
                "app_status": "idle",
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
                    "active_users": 0,
                    "active_sessions": 0,
                    "total_requests": 0
                }
            }
            
            # Register main state
            success = self.register_state(
                state_id="main_state",
                state_type=StateType.SYSTEM,
                initial_data=main_state_data,
                allowed_transitions=["update", "activate", "deactivate"]
            )
            
            if success:
                else:
                except Exception as e:
            def health_check(self) -> Dict[str, Any]:
        """Perform health check on the state manager."""
        try:
            active_states = len(self.get_active_states())
            total_states = len(self._states)
            
            return {
                'status': 'healthy',
                'active_states': active_states,
                'total_states': total_states,
                'redis_available': self.redis_manager.ping() if hasattr(self.redis_manager, 'ping') else True,
                'database_available': self.database_manager.available if hasattr(self.database_manager, 'available') else True
            }
        except Exception as e:
            return {
                'status': 'unhealthy',
                'error': str(e)
            } 