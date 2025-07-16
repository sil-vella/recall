# Managers Documentation - Python Base 04

## Overview

The Python Base 04 framework uses a manager-based architecture where each manager is responsible for a specific domain of functionality. This document provides comprehensive documentation for all managers in the system.

## Manager Architecture

### Manager Pattern

All managers follow a consistent pattern:
- **Singleton Pattern**: Most managers are singletons to ensure consistent state
- **Dependency Injection**: Managers can depend on each other through the AppManager
- **Lifecycle Management**: Proper initialization and cleanup
- **Health Monitoring**: Each manager provides health status
- **Error Handling**: Comprehensive error handling and recovery

## Core Managers

### 1. AppManager

**File**: `core/managers/app_manager.py`  
**Purpose**: Main application orchestrator and lifecycle manager

#### Key Responsibilities

- **Application Initialization**: Orchestrates the initialization of all components
- **Manager Coordination**: Coordinates all other managers
- **Flask Integration**: Integrates with Flask application
- **Module Management**: Manages module lifecycle
- **Health Monitoring**: Provides application health status

#### Key Methods

```python
class AppManager:
    def __init__(self):
        # Initialize all manager references
        self.services_manager = ServicesManager()
        self.hooks_manager = HooksManager()
        self.module_manager = ModuleManager()
        # ... other managers
    
    def initialize(self, app):
        """Initialize all components and managers"""
        # Initialize database managers
        # Initialize Redis manager
        # Initialize state manager
        # Initialize JWT manager
        # Initialize action discovery
        # Initialize WebSocket manager
    
    def is_initialized(self):
        """Check if the AppManager is properly initialized"""
    
    def check_database_connection(self):
        """Check database connection health"""
    
    def check_redis_connection(self):
        """Check Redis connection health"""
    
    def run(self, app, **kwargs):
        """Run the Flask application"""
```

#### Usage Example

```python
# Initialize AppManager
app_manager = AppManager()

# Initialize with Flask app
app_manager.initialize(app)

# Check health
if app_manager.is_initialized():
    print("Application is healthy")
```

### 2. StateManager

**File**: `core/managers/state_manager.py`  
**Purpose**: Centralized state management with persistence

#### Key Features

- **State Types**: System, User, Session, Resource, Feature, Subscription
- **State Transitions**: Create, Update, Delete, Activate, Deactivate, etc.
- **Persistence**: Redis and database persistence
- **History Tracking**: State change history
- **Callbacks**: State change notifications

#### Key Methods

```python
class StateManager:
    def register_state(self, state_id: str, state_type: StateType, 
                      initial_data: Dict[str, Any], 
                      allowed_transitions: Optional[List[str]] = None) -> bool:
        """Register a new state in the system"""
    
    def get_state(self, state_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve a state by ID"""
    
    def update_state(self, state_id: str, new_data: Dict[str, Any], 
                    transition: Optional[StateTransition] = None) -> bool:
        """Update an existing state"""
    
    def delete_state(self, state_id: str) -> bool:
        """Delete a state"""
    
    def get_state_history(self, state_id: str, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """Get state change history"""
    
    def register_callback(self, state_id: str, callback: Callable) -> bool:
        """Register a callback for state changes"""
    
    def health_check(self) -> Dict[str, Any]:
        """Perform health check"""
```

#### Usage Example

```python
# Get state manager
state_manager = app_manager.get_state_manager()

# Register a new state
state_manager.register_state(
    state_id="user_123_session",
    state_type=StateType.SESSION,
    initial_data={"user_id": "123", "login_time": "2024-01-01T10:00:00Z"},
    allowed_transitions=["update", "delete", "expire"]
)

# Update state
state_manager.update_state(
    state_id="user_123_session",
    new_data={"last_activity": "2024-01-01T11:00:00Z"},
    transition=StateTransition.UPDATE
)

# Get state
state = state_manager.get_state("user_123_session")
```

### 3. DatabaseManager

**File**: `core/managers/database_manager.py`  
**Purpose**: Database operations and connection management

#### Key Features

- **Multi-Database Support**: MongoDB and PostgreSQL
- **Connection Pooling**: Efficient connection management
- **Role-Based Access**: Read/write, read-only, admin roles
- **Health Monitoring**: Connection health checks
- **Retry Mechanisms**: Automatic retry for transient failures

#### Key Methods

```python
class DatabaseManager:
    def __init__(self, role="read_write"):
        """Initialize database manager with specific role"""
    
    def check_connection(self) -> bool:
        """Check database connection health"""
    
    def execute_query(self, query: str, params: Dict = None) -> Any:
        """Execute a database query"""
    
    def execute_transaction(self, operations: List[Dict]) -> bool:
        """Execute multiple operations in a transaction"""
    
    def get_connection_pool_status(self) -> Dict[str, Any]:
        """Get connection pool status"""
    
    def health_check(self) -> Dict[str, Any]:
        """Perform health check"""
```

#### Usage Example

```python
# Get database manager
db_manager = app_manager.get_db_manager(role="read_write")

# Check connection
if db_manager.check_connection():
    print("Database connection is healthy")

# Execute query
result = db_manager.execute_query(
    "SELECT * FROM users WHERE id = %s",
    {"id": 123}
)

# Execute transaction
operations = [
    {"type": "insert", "table": "users", "data": {"name": "John"}},
    {"type": "update", "table": "sessions", "data": {"user_id": 123}}
]
success = db_manager.execute_transaction(operations)
```

### 4. RedisManager

**File**: `core/managers/redis_manager.py`  
**Purpose**: Redis operations and caching management

#### Key Features

- **Connection Pooling**: Efficient Redis connection management
- **SSL/TLS Support**: Secure Redis connections
- **Cluster Support**: Redis cluster operations
- **Pub/Sub**: Publish/subscribe functionality
- **Health Monitoring**: Redis health checks

#### Key Methods

```python
class RedisManager:
    def __init__(self):
        """Initialize Redis manager"""
    
    def ping(self) -> bool:
        """Ping Redis server"""
    
    def get(self, key: str) -> Any:
        """Get value from Redis"""
    
    def set(self, key: str, value: Any, ttl: int = None) -> bool:
        """Set value in Redis with optional TTL"""
    
    def delete(self, key: str) -> bool:
        """Delete key from Redis"""
    
    def publish(self, channel: str, message: Any) -> int:
        """Publish message to channel"""
    
    def subscribe(self, channel: str, callback: Callable) -> bool:
        """Subscribe to channel"""
    
    def health_check(self) -> Dict[str, Any]:
        """Perform health check"""
```

#### Usage Example

```python
# Get Redis manager
redis_manager = app_manager.get_redis_manager()

# Check connection
if redis_manager.ping():
    print("Redis connection is healthy")

# Set value
redis_manager.set("user:123:session", {"user_id": 123, "login_time": "2024-01-01T10:00:00Z"}, ttl=3600)

# Get value
session_data = redis_manager.get("user:123:session")

# Publish message
redis_manager.publish("user_events", {"user_id": 123, "event": "login"})
```

### 5. JWTManager

**File**: `core/managers/jwt_manager.py`  
**Purpose**: JWT token management and authentication

#### Key Features

- **Token Generation**: Create JWT tokens
- **Token Validation**: Validate and decode tokens
- **Token Refresh**: Automatic token refresh
- **Blacklisting**: Token blacklisting for logout
- **Security**: Secure token handling

#### Key Methods

```python
class JWTManager:
    def __init__(self, redis_manager: RedisManager):
        """Initialize JWT manager"""
    
    def create_access_token(self, user_id: str, additional_claims: Dict = None) -> str:
        """Create access token"""
    
    def create_refresh_token(self, user_id: str) -> str:
        """Create refresh token"""
    
    def validate_token(self, token: str) -> Dict[str, Any]:
        """Validate and decode token"""
    
    def refresh_token(self, refresh_token: str) -> Dict[str, str]:
        """Refresh access token using refresh token"""
    
    def blacklist_token(self, token: str) -> bool:
        """Blacklist a token"""
    
    def is_token_blacklisted(self, token: str) -> bool:
        """Check if token is blacklisted"""
```

#### Usage Example

```python
# Get JWT manager
jwt_manager = app_manager.jwt_manager

# Create tokens
access_token = jwt_manager.create_access_token(
    user_id="123",
    additional_claims={"role": "user", "permissions": ["read", "write"]}
)
refresh_token = jwt_manager.create_refresh_token(user_id="123")

# Validate token
try:
    payload = jwt_manager.validate_token(access_token)
    user_id = payload["user_id"]
except Exception as e:
    print(f"Token validation failed: {e}")

# Refresh token
new_tokens = jwt_manager.refresh_token(refresh_token)
```

### 6. ApiKeyManager

**File**: `core/managers/api_key_manager.py`  
**Purpose**: API key management and authentication

#### Key Features

- **API Key Generation**: Generate secure API keys
- **Key Validation**: Validate API keys
- **Permission Management**: API key permissions and scopes
- **Rate Limiting**: API key-based rate limiting
- **Audit Logging**: API key usage logging

#### Key Methods

```python
class ApiKeyManager:
    def __init__(self):
        """Initialize API key manager"""
    
    def generate_api_key(self, user_id: str, permissions: List[str] = None) -> str:
        """Generate new API key"""
    
    def validate_api_key(self, api_key: str) -> Dict[str, Any]:
        """Validate API key and return user info"""
    
    def revoke_api_key(self, api_key: str) -> bool:
        """Revoke an API key"""
    
    def get_api_key_info(self, api_key: str) -> Dict[str, Any]:
        """Get API key information"""
    
    def update_api_key_permissions(self, api_key: str, permissions: List[str]) -> bool:
        """Update API key permissions"""
```

#### Usage Example

```python
# Get API key manager
api_key_manager = app_manager.api_key_manager

# Generate API key
api_key = api_key_manager.generate_api_key(
    user_id="123",
    permissions=["read", "write", "admin"]
)

# Validate API key
try:
    key_info = api_key_manager.validate_api_key(api_key)
    user_id = key_info["user_id"]
    permissions = key_info["permissions"]
except Exception as e:
    print(f"API key validation failed: {e}")

# Revoke API key
api_key_manager.revoke_api_key(api_key)
```

### 7. VaultManager

**File**: `core/managers/vault_manager.py`  
**Purpose**: HashiCorp Vault integration for secret management

#### Key Features

- **Secret Retrieval**: Secure secret retrieval from Vault
- **Authentication**: Vault authentication (AppRole, Kubernetes)
- **Secret Rotation**: Automatic secret rotation
- **Health Monitoring**: Vault connection health
- **Fallback Support**: File-based secret fallback

#### Key Methods

```python
class VaultManager:
    def __init__(self):
        """Initialize Vault manager"""
    
    def get_secret_value(self, path: str, key: str) -> str:
        """Get secret value from Vault"""
    
    def set_secret_value(self, path: str, key: str, value: str) -> bool:
        """Set secret value in Vault"""
    
    def delete_secret(self, path: str) -> bool:
        """Delete secret from Vault"""
    
    def health_check(self) -> Dict[str, Any]:
        """Perform Vault health check"""
    
    def get_connection_info(self) -> Dict[str, Any]:
        """Get Vault connection information"""
```

#### Usage Example

```python
# Get Vault manager
vault_manager = app_manager.vault_manager

# Get secret
try:
    db_password = vault_manager.get_secret_value("flask-app/mongodb", "root_password")
    jwt_secret = vault_manager.get_secret_value("flask-app/app", "secret_key")
except Exception as e:
    print(f"Failed to get secrets from Vault: {e}")

# Check Vault health
vault_health = vault_manager.health_check()
if vault_health["status"] == "healthy":
    print("Vault is healthy")
```

### 8. RateLimiterManager

**File**: `core/managers/rate_limiter_manager.py`  
**Purpose**: Multi-level rate limiting and protection

#### Key Features

- **Multi-Level Limiting**: IP, user, and API key rate limiting
- **Configurable Limits**: Customizable rate limits
- **Auto-Banning**: Automatic banning for violations
- **Header Support**: Rate limit headers in responses
- **Redis Backend**: Redis-based rate limiting storage

#### Key Methods

```python
class RateLimiterManager:
    def __init__(self):
        """Initialize rate limiter manager"""
    
    def check_rate_limit(self, limit_types: List[str]) -> Dict[str, Any]:
        """Check rate limits for specified types"""
    
    def get_rate_limit_info(self, identifier: str, limit_type: str) -> Dict[str, Any]:
        """Get rate limit information"""
    
    def reset_rate_limit(self, identifier: str, limit_type: str) -> bool:
        """Reset rate limit for identifier"""
    
    def ban_identifier(self, identifier: str, duration: int = None) -> bool:
        """Ban an identifier"""
    
    def unban_identifier(self, identifier: str) -> bool:
        """Unban an identifier"""
```

#### Usage Example

```python
# Get rate limiter manager
rate_limiter = app_manager.rate_limiter_manager

# Check rate limits
result = rate_limiter.check_rate_limit(['ip', 'user', 'api_key'])
if not result['allowed']:
    print(f"Rate limit exceeded: {result['exceeded_types']}")
    return

# Get rate limit info
info = rate_limiter.get_rate_limit_info("192.168.1.1", "ip")
print(f"Remaining requests: {info['remaining']}")

# Ban IP for violations
rate_limiter.ban_identifier("192.168.1.1", duration=3600)
```

### 9. ActionDiscoveryManager

**File**: `core/managers/action_discovery_manager.py`  
**Purpose**: Dynamic action registration and execution

#### Key Features

- **YAML Configuration**: Action definitions in YAML files
- **Dynamic Registration**: Automatic action discovery
- **Parameter Validation**: Automatic parameter validation
- **Execution Routing**: Dynamic action execution
- **Error Handling**: Comprehensive error handling

#### Key Methods

```python
class ActionDiscoveryManager:
    def __init__(self, app_manager: AppManager):
        """Initialize action discovery manager"""
    
    def discover_all_actions(self) -> Dict[str, Any]:
        """Discover all actions from YAML files"""
    
    def find_action(self, action_name: str) -> Optional[Dict[str, Any]]:
        """Find action by name"""
    
    def validate_action_args(self, action_info: Dict, args: Dict) -> Dict[str, Any]:
        """Validate action arguments"""
    
    def execute_action_logic(self, action_info: Dict, args: Dict) -> Any:
        """Execute action logic"""
    
    def list_all_actions(self) -> Dict[str, Any]:
        """List all available actions"""
```

#### Usage Example

```python
# Get action discovery manager
action_manager = app_manager.action_discovery_manager

# Discover actions
action_manager.discover_all_actions()

# Find action
action_info = action_manager.find_action("create_user")
if action_info:
    print(f"Action found: {action_info['module']}")

# Execute action
args = {"username": "john", "email": "john@example.com"}
result = action_manager.execute_action_logic(action_info, args)

# List all actions
actions = action_manager.list_all_actions()
for action_name, info in actions['actions'].items():
    print(f"Action: {action_name} -> Module: {info['module']}")
```

### 10. WebSocketManager

**File**: `core/managers/websockets/websocket_manager.py`  
**Purpose**: WebSocket management and real-time communication

#### Key Features

- **Room Management**: Dynamic room creation and management
- **Authentication**: JWT-based WebSocket authentication
- **Rate Limiting**: Message rate limiting
- **Presence Tracking**: User presence and status
- **Session Management**: WebSocket session lifecycle

#### Key Methods

```python
class WebSocketManager:
    def __init__(self):
        """Initialize WebSocket manager"""
    
    def initialize(self, app, use_builtin_handlers: bool = True):
        """Initialize WebSocket with Flask app"""
    
    def emit_to_room(self, room: str, event: str, data: Any):
        """Emit event to room"""
    
    def join_room(self, room: str, sid: str = None):
        """Join a room"""
    
    def leave_room(self, room: str, sid: str = None):
        """Leave a room"""
    
    def get_room_info(self, room: str) -> Dict[str, Any]:
        """Get room information"""
    
    def health_check(self) -> Dict[str, Any]:
        """Perform health check"""
```

#### Usage Example

```python
# Get WebSocket manager
ws_manager = app_manager.get_websocket_manager()

# Initialize with Flask app
ws_manager.initialize(app)

# Emit to room
ws_manager.emit_to_room("user_123", "notification", {"message": "Hello!"})

# Join room
ws_manager.join_room("user_123", sid="socket_123")

# Get room info
room_info = ws_manager.get_room_info("user_123")
print(f"Users in room: {room_info['users']}")
```

## Manager Integration

### Manager Dependencies

```python
# Manager dependency graph
AppManager
├── StateManager (depends on RedisManager, DatabaseManager)
├── DatabaseManager (independent)
├── RedisManager (independent)
├── JWTManager (depends on RedisManager)
├── ApiKeyManager (depends on DatabaseManager)
├── VaultManager (independent)
├── RateLimiterManager (depends on RedisManager)
├── ActionDiscoveryManager (depends on AppManager)
├── WebSocketManager (depends on JWTManager)
├── ModuleManager (depends on AppManager)
├── ServicesManager (independent)
└── HooksManager (independent)
```

### Manager Initialization Order

1. **Independent Managers**: ServicesManager, HooksManager, VaultManager
2. **Database Managers**: DatabaseManager, RedisManager
3. **Authentication Managers**: JWTManager, ApiKeyManager
4. **State Manager**: StateManager (depends on Redis and Database)
5. **Rate Limiter**: RateLimiterManager (depends on Redis)
6. **Action Discovery**: ActionDiscoveryManager (depends on AppManager)
7. **WebSocket**: WebSocketManager (depends on JWT)
8. **Module Manager**: ModuleManager (depends on AppManager)

### Health Monitoring

Each manager provides a `health_check()` method that returns:

```python
{
    "status": "healthy|unhealthy|degraded",
    "details": "Description of health status",
    "metrics": {
        "connections": 10,
        "errors": 0,
        "response_time": 0.05
    },
    "dependencies": {
        "redis": "healthy",
        "database": "healthy"
    }
}
```

## Best Practices

### 1. Manager Usage

- **Singleton Pattern**: Use managers as singletons through AppManager
- **Error Handling**: Always handle manager method exceptions
- **Health Checks**: Regularly check manager health
- **Resource Cleanup**: Properly dispose of managers when needed

### 2. State Management

- **State Registration**: Always register states with proper types
- **State Validation**: Validate state transitions
- **State Callbacks**: Use callbacks for state change notifications
- **State Persistence**: Ensure proper state persistence

### 3. Authentication

- **Token Management**: Use JWTManager for all token operations
- **API Key Security**: Secure API key generation and validation
- **Rate Limiting**: Apply rate limiting to authenticated endpoints
- **Audit Logging**: Log all authentication events

### 4. Database Operations

- **Connection Pooling**: Use connection pooling for efficiency
- **Transaction Management**: Use transactions for data consistency
- **Error Recovery**: Implement proper error recovery mechanisms
- **Health Monitoring**: Monitor database health regularly

### 5. Caching Strategy

- **Cache Keys**: Use consistent cache key naming
- **TTL Management**: Set appropriate TTL for cached data
- **Cache Invalidation**: Implement strategic cache invalidation
- **Memory Management**: Monitor cache memory usage

This comprehensive manager system provides a robust foundation for building scalable and maintainable applications with proper separation of concerns and comprehensive functionality. 