# API Reference - Python Base 04

## Overview

This document provides a comprehensive API reference for the Python Base 04 framework, including all managers, modules, utilities, and core components.

## Table of Contents

1. [Core Managers](#core-managers)
2. [Module System](#module-system)
3. [Configuration System](#configuration-system)
4. [Logging System](#logging-system)
5. [Utility Functions](#utility-functions)
6. [Base Classes](#base-classes)
7. [WebSocket API](#websocket-api)
8. [Health Check API](#health-check-api)

## Core Managers

### AppManager

**File**: `core/managers/app_manager.py`

#### Class Definition

```python
class AppManager:
    def __init__(self) -> None
```

#### Methods

##### `initialize(app: Flask) -> None`

Initialize all components and managers with the Flask application.

**Parameters**:
- `app` (Flask): Flask application instance

**Raises**:
- `RuntimeError`: If Flask app is invalid

**Example**:
```python
app_manager = AppManager()
app_manager.initialize(app)
```

##### `is_initialized() -> bool`

Check if the AppManager is properly initialized.

**Returns**:
- `bool`: True if initialized, False otherwise

**Example**:
```python
if app_manager.is_initialized():
    print("Application is ready")
```

##### `check_database_connection() -> bool`

Check database connection health.

**Returns**:
- `bool`: True if database is healthy, False otherwise

**Example**:
```python
if app_manager.check_database_connection():
    print("Database is healthy")
```

##### `check_redis_connection() -> bool`

Check Redis connection health.

**Returns**:
- `bool`: True if Redis is healthy, False otherwise

**Example**:
```python
if app_manager.check_redis_connection():
    print("Redis is healthy")
```

##### `get_db_manager(role: str = "read_write") -> DatabaseManager`

Get database manager instance.

**Parameters**:
- `role` (str): Database role ("read_write", "read_only", "admin")

**Returns**:
- `DatabaseManager`: Database manager instance

**Example**:
```python
db_manager = app_manager.get_db_manager(role="read_write")
```

##### `get_redis_manager() -> RedisManager`

Get Redis manager instance.

**Returns**:
- `RedisManager`: Redis manager instance

**Example**:
```python
redis_manager = app_manager.get_redis_manager()
```

##### `get_state_manager() -> StateManager`

Get state manager instance.

**Returns**:
- `StateManager`: State manager instance

**Example**:
```python
state_manager = app_manager.get_state_manager()
```

##### `get_websocket_manager() -> WebSocketManager`

Get WebSocket manager instance.

**Returns**:
- `WebSocketManager`: WebSocket manager instance

**Example**:
```python
ws_manager = app_manager.get_websocket_manager()
```

##### `run(app: Flask, **kwargs) -> None`

Run the Flask application.

**Parameters**:
- `app` (Flask): Flask application instance
- `**kwargs`: Additional arguments for Flask run

**Example**:
```python
app_manager.run(app, host="0.0.0.0", port=5001)
```

### StateManager

**File**: `core/managers/state_manager.py`

#### Class Definition

```python
class StateManager:
    def __init__(self, redis_manager: Optional[RedisManager] = None, 
                 database_manager: Optional[DatabaseManager] = None) -> None
```

#### Enums

##### `StateType`

```python
class StateType(Enum):
    SYSTEM = "system"
    USER = "user"
    SESSION = "session"
    RESOURCE = "resource"
    FEATURE = "feature"
    SUBSCRIPTION = "subscription"
```

##### `StateTransition`

```python
class StateTransition(Enum):
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"
    ACTIVATE = "activate"
    DEACTIVATE = "deactivate"
    SUSPEND = "suspend"
    RESUME = "resume"
    EXPIRE = "expire"
    RENEW = "renew"
```

#### Methods

##### `register_state(state_id: str, state_type: StateType, initial_data: Dict[str, Any], allowed_transitions: Optional[List[str]] = None) -> bool`

Register a new state in the system.

**Parameters**:
- `state_id` (str): Unique state identifier
- `state_type` (StateType): Type of state
- `initial_data` (Dict[str, Any]): Initial state data
- `allowed_transitions` (Optional[List[str]]): Allowed transition types

**Returns**:
- `bool`: True if registration successful

**Example**:
```python
state_manager.register_state(
    state_id="user_123_session",
    state_type=StateType.SESSION,
    initial_data={"user_id": "123", "login_time": "2024-01-01T10:00:00Z"},
    allowed_transitions=["update", "delete", "expire"]
)
```

##### `get_state(state_id: str) -> Optional[Dict[str, Any]]`

Retrieve a state by ID.

**Parameters**:
- `state_id` (str): State identifier

**Returns**:
- `Optional[Dict[str, Any]]`: State data or None if not found

**Example**:
```python
state = state_manager.get_state("user_123_session")
if state:
    print(f"State data: {state['data']}")
```

##### `update_state(state_id: str, new_data: Dict[str, Any], transition: Optional[StateTransition] = None) -> bool`

Update an existing state.

**Parameters**:
- `state_id` (str): State identifier
- `new_data` (Dict[str, Any]): New state data
- `transition` (Optional[StateTransition]): Transition type

**Returns**:
- `bool`: True if update successful

**Example**:
```python
state_manager.update_state(
    state_id="user_123_session",
    new_data={"last_activity": "2024-01-01T11:00:00Z"},
    transition=StateTransition.UPDATE
)
```

##### `delete_state(state_id: str) -> bool`

Delete a state.

**Parameters**:
- `state_id` (str): State identifier

**Returns**:
- `bool`: True if deletion successful

**Example**:
```python
state_manager.delete_state("user_123_session")
```

##### `get_state_history(state_id: str, limit: Optional[int] = None) -> List[Dict[str, Any]]`

Get state change history.

**Parameters**:
- `state_id` (str): State identifier
- `limit` (Optional[int]): Maximum number of history entries

**Returns**:
- `List[Dict[str, Any]]`: State history

**Example**:
```python
history = state_manager.get_state_history("user_123_session", limit=10)
for entry in history:
    print(f"Transition: {entry['transition']}, Data: {entry['data']}")
```

##### `register_callback(state_id: str, callback: Callable) -> bool`

Register a callback for state changes.

**Parameters**:
- `state_id` (str): State identifier
- `callback` (Callable): Callback function

**Returns**:
- `bool`: True if registration successful

**Example**:
```python
def state_change_callback(state_id: str, transition: str, data: Dict[str, Any]):
    print(f"State {state_id} changed: {transition}")

state_manager.register_callback("user_123_session", state_change_callback)
```

##### `get_states_by_type(state_type: StateType) -> List[Dict[str, Any]]`

Get all states of a specific type.

**Parameters**:
- `state_type` (StateType): State type

**Returns**:
- `List[Dict[str, Any]]`: List of states

**Example**:
```python
user_states = state_manager.get_states_by_type(StateType.USER)
for state in user_states:
    print(f"User state: {state['id']}")
```

##### `get_active_states() -> List[Dict[str, Any]]`

Get all active states.

**Returns**:
- `List[Dict[str, Any]]`: List of active states

**Example**:
```python
active_states = state_manager.get_active_states()
print(f"Active states: {len(active_states)}")
```

##### `health_check() -> Dict[str, Any]`

Perform health check.

**Returns**:
- `Dict[str, Any]`: Health status

**Example**:
```python
health = state_manager.health_check()
print(f"State manager health: {health['status']}")
```

### DatabaseManager

**File**: `core/managers/database_manager.py`

#### Class Definition

```python
class DatabaseManager:
    def __init__(self, role: str = "read_write") -> None
```

#### Methods

##### `check_connection() -> bool`

Check database connection health.

**Returns**:
- `bool`: True if connection is healthy

**Example**:
```python
if db_manager.check_connection():
    print("Database connection is healthy")
```

##### `execute_query(query: str, params: Dict = None) -> Any`

Execute a database query.

**Parameters**:
- `query` (str): SQL query
- `params` (Dict): Query parameters

**Returns**:
- `Any`: Query result

**Example**:
```python
result = db_manager.execute_query(
    "SELECT * FROM users WHERE id = %s",
    {"id": 123}
)
```

##### `execute_transaction(operations: List[Dict]) -> bool`

Execute multiple operations in a transaction.

**Parameters**:
- `operations` (List[Dict]): List of operations

**Returns**:
- `bool`: True if transaction successful

**Example**:
```python
operations = [
    {"type": "insert", "table": "users", "data": {"name": "John"}},
    {"type": "update", "table": "sessions", "data": {"user_id": 123}}
]
success = db_manager.execute_transaction(operations)
```

##### `get_connection_pool_status() -> Dict[str, Any]`

Get connection pool status.

**Returns**:
- `Dict[str, Any]`: Connection pool information

**Example**:
```python
pool_status = db_manager.get_connection_pool_status()
print(f"Active connections: {pool_status['active_connections']}")
```

##### `health_check() -> Dict[str, Any]`

Perform health check.

**Returns**:
- `Dict[str, Any]`: Health status

**Example**:
```python
health = db_manager.health_check()
print(f"Database health: {health['status']}")
```

### RedisManager

**File**: `core/managers/redis_manager.py`

#### Class Definition

```python
class RedisManager:
    def __init__(self) -> None
```

#### Methods

##### `ping() -> bool`

Ping Redis server.

**Returns**:
- `bool`: True if Redis is responding

**Example**:
```python
if redis_manager.ping():
    print("Redis is responding")
```

##### `get(key: str) -> Any`

Get value from Redis.

**Parameters**:
- `key` (str): Redis key

**Returns**:
- `Any`: Value from Redis

**Example**:
```python
value = redis_manager.get("user:123:session")
if value:
    print(f"Session data: {value}")
```

##### `set(key: str, value: Any, ttl: int = None) -> bool`

Set value in Redis with optional TTL.

**Parameters**:
- `key` (str): Redis key
- `value` (Any): Value to store
- `ttl` (int): Time to live in seconds

**Returns**:
- `bool`: True if operation successful

**Example**:
```python
redis_manager.set("user:123:session", {"user_id": 123}, ttl=3600)
```

##### `delete(key: str) -> bool`

Delete key from Redis.

**Parameters**:
- `key` (str): Redis key

**Returns**:
- `bool`: True if deletion successful

**Example**:
```python
redis_manager.delete("user:123:session")
```

##### `publish(channel: str, message: Any) -> int`

Publish message to channel.

**Parameters**:
- `channel` (str): Channel name
- `message` (Any): Message to publish

**Returns**:
- `int`: Number of subscribers

**Example**:
```python
subscribers = redis_manager.publish("user_events", {"user_id": 123, "event": "login"})
print(f"Message sent to {subscribers} subscribers")
```

##### `subscribe(channel: str, callback: Callable) -> bool`

Subscribe to channel.

**Parameters**:
- `channel` (str): Channel name
- `callback` (Callable): Callback function

**Returns**:
- `bool`: True if subscription successful

**Example**:
```python
def message_handler(channel: str, message: Any):
    print(f"Received message on {channel}: {message}")

redis_manager.subscribe("user_events", message_handler)
```

##### `health_check() -> Dict[str, Any]`

Perform health check.

**Returns**:
- `Dict[str, Any]`: Health status

**Example**:
```python
health = redis_manager.health_check()
print(f"Redis health: {health['status']}")
```

### JWTManager

**File**: `core/managers/jwt_manager.py`

#### Class Definition

```python
class JWTManager:
    def __init__(self, redis_manager: RedisManager) -> None
```

#### Methods

##### `create_access_token(user_id: str, additional_claims: Dict = None) -> str`

Create access token.

**Parameters**:
- `user_id` (str): User identifier
- `additional_claims` (Dict): Additional JWT claims

**Returns**:
- `str`: JWT access token

**Example**:
```python
token = jwt_manager.create_access_token(
    user_id="123",
    additional_claims={"role": "user", "permissions": ["read", "write"]}
)
```

##### `create_refresh_token(user_id: str) -> str`

Create refresh token.

**Parameters**:
- `user_id` (str): User identifier

**Returns**:
- `str`: JWT refresh token

**Example**:
```python
refresh_token = jwt_manager.create_refresh_token(user_id="123")
```

##### `validate_token(token: str) -> Dict[str, Any]`

Validate and decode token.

**Parameters**:
- `token` (str): JWT token

**Returns**:
- `Dict[str, Any]`: Token payload

**Raises**:
- `Exception`: If token is invalid

**Example**:
```python
try:
    payload = jwt_manager.validate_token(token)
    user_id = payload["user_id"]
except Exception as e:
    print(f"Token validation failed: {e}")
```

##### `refresh_token(refresh_token: str) -> Dict[str, str]`

Refresh access token using refresh token.

**Parameters**:
- `refresh_token` (str): Refresh token

**Returns**:
- `Dict[str, str]`: New access and refresh tokens

**Example**:
```python
new_tokens = jwt_manager.refresh_token(refresh_token)
access_token = new_tokens["access_token"]
new_refresh_token = new_tokens["refresh_token"]
```

##### `blacklist_token(token: str) -> bool`

Blacklist a token.

**Parameters**:
- `token` (str): Token to blacklist

**Returns**:
- `bool`: True if blacklisting successful

**Example**:
```python
jwt_manager.blacklist_token(token)
```

##### `is_token_blacklisted(token: str) -> bool`

Check if token is blacklisted.

**Parameters**:
- `token` (str): Token to check

**Returns**:
- `bool`: True if token is blacklisted

**Example**:
```python
if jwt_manager.is_token_blacklisted(token):
    print("Token is blacklisted")
```

### ApiKeyManager

**File**: `core/managers/api_key_manager.py`

#### Class Definition

```python
class ApiKeyManager:
    def __init__(self) -> None
```

#### Methods

##### `generate_api_key(user_id: str, permissions: List[str] = None) -> str`

Generate new API key.

**Parameters**:
- `user_id` (str): User identifier
- `permissions` (List[str]): API key permissions

**Returns**:
- `str`: Generated API key

**Example**:
```python
api_key = api_key_manager.generate_api_key(
    user_id="123",
    permissions=["read", "write", "admin"]
)
```

##### `validate_api_key(api_key: str) -> Dict[str, Any]`

Validate API key and return user info.

**Parameters**:
- `api_key` (str): API key to validate

**Returns**:
- `Dict[str, Any]`: API key information

**Raises**:
- `Exception`: If API key is invalid

**Example**:
```python
try:
    key_info = api_key_manager.validate_api_key(api_key)
    user_id = key_info["user_id"]
    permissions = key_info["permissions"]
except Exception as e:
    print(f"API key validation failed: {e}")
```

##### `revoke_api_key(api_key: str) -> bool`

Revoke an API key.

**Parameters**:
- `api_key` (str): API key to revoke

**Returns**:
- `bool`: True if revocation successful

**Example**:
```python
api_key_manager.revoke_api_key(api_key)
```

##### `get_api_key_info(api_key: str) -> Dict[str, Any]`

Get API key information.

**Parameters**:
- `api_key` (str): API key

**Returns**:
- `Dict[str, Any]`: API key information

**Example**:
```python
key_info = api_key_manager.get_api_key_info(api_key)
print(f"Key created: {key_info['created_at']}")
```

##### `update_api_key_permissions(api_key: str, permissions: List[str]) -> bool`

Update API key permissions.

**Parameters**:
- `api_key` (str): API key
- `permissions` (List[str]): New permissions

**Returns**:
- `bool`: True if update successful

**Example**:
```python
api_key_manager.update_api_key_permissions(api_key, ["read", "write"])
```

### VaultManager

**File**: `core/managers/vault_manager.py`

#### Class Definition

```python
class VaultManager:
    def __init__(self) -> None
```

#### Methods

##### `get_secret_value(path: str, key: str) -> str`

Get secret value from Vault.

**Parameters**:
- `path` (str): Secret path
- `key` (str): Secret key

**Returns**:
- `str`: Secret value

**Example**:
```python
db_password = vault_manager.get_secret_value("flask-app/mongodb", "root_password")
```

##### `set_secret_value(path: str, key: str, value: str) -> bool`

Set secret value in Vault.

**Parameters**:
- `path` (str): Secret path
- `key` (str): Secret key
- `value` (str): Secret value

**Returns**:
- `bool`: True if operation successful

**Example**:
```python
vault_manager.set_secret_value("flask-app/app", "secret_key", "new-secret-key")
```

##### `delete_secret(path: str) -> bool`

Delete secret from Vault.

**Parameters**:
- `path` (str): Secret path

**Returns**:
- `bool`: True if deletion successful

**Example**:
```python
vault_manager.delete_secret("flask-app/old-secret")
```

##### `health_check() -> Dict[str, Any]`

Perform Vault health check.

**Returns**:
- `Dict[str, Any]`: Health status

**Example**:
```python
health = vault_manager.health_check()
print(f"Vault health: {health['status']}")
```

##### `get_connection_info() -> Dict[str, Any]`

Get Vault connection information.

**Returns**:
- `Dict[str, Any]`: Connection information

**Example**:
```python
conn_info = vault_manager.get_connection_info()
print(f"Vault address: {conn_info['address']}")
```

### RateLimiterManager

**File**: `core/managers/rate_limiter_manager.py`

#### Class Definition

```python
class RateLimiterManager:
    def __init__(self) -> None
```

#### Methods

##### `check_rate_limit(limit_types: List[str]) -> Dict[str, Any]`

Check rate limits for specified types.

**Parameters**:
- `limit_types` (List[str]): Types of limits to check ("ip", "user", "api_key")

**Returns**:
- `Dict[str, Any]`: Rate limit check result

**Example**:
```python
result = rate_limiter.check_rate_limit(['ip', 'user', 'api_key'])
if not result['allowed']:
    print(f"Rate limit exceeded: {result['exceeded_types']}")
```

##### `get_rate_limit_info(identifier: str, limit_type: str) -> Dict[str, Any]`

Get rate limit information.

**Parameters**:
- `identifier` (str): Identifier (IP, user ID, API key)
- `limit_type` (str): Type of limit

**Returns**:
- `Dict[str, Any]`: Rate limit information

**Example**:
```python
info = rate_limiter.get_rate_limit_info("192.168.1.1", "ip")
print(f"Remaining requests: {info['remaining']}")
```

##### `reset_rate_limit(identifier: str, limit_type: str) -> bool`

Reset rate limit for identifier.

**Parameters**:
- `identifier` (str): Identifier
- `limit_type` (str): Type of limit

**Returns**:
- `bool`: True if reset successful

**Example**:
```python
rate_limiter.reset_rate_limit("192.168.1.1", "ip")
```

##### `ban_identifier(identifier: str, duration: int = None) -> bool`

Ban an identifier.

**Parameters**:
- `identifier` (str): Identifier to ban
- `duration` (int): Ban duration in seconds

**Returns**:
- `bool`: True if ban successful

**Example**:
```python
rate_limiter.ban_identifier("192.168.1.1", duration=3600)
```

##### `unban_identifier(identifier: str) -> bool`

Unban an identifier.

**Parameters**:
- `identifier` (str): Identifier to unban

**Returns**:
- `bool`: True if unban successful

**Example**:
```python
rate_limiter.unban_identifier("192.168.1.1")
```

### ActionDiscoveryManager

**File**: `core/managers/action_discovery_manager.py`

#### Class Definition

```python
class ActionDiscoveryManager:
    def __init__(self, app_manager: AppManager) -> None
```

#### Methods

##### `discover_all_actions() -> Dict[str, Any]`

Discover all actions from YAML files.

**Returns**:
- `Dict[str, Any]`: Discovery result

**Example**:
```python
result = action_manager.discover_all_actions()
print(f"Discovered {result['total_actions']} actions")
```

##### `find_action(action_name: str) -> Optional[Dict[str, Any]]`

Find action by name.

**Parameters**:
- `action_name` (str): Action name

**Returns**:
- `Optional[Dict[str, Any]]`: Action information or None

**Example**:
```python
action_info = action_manager.find_action("create_user")
if action_info:
    print(f"Action found: {action_info['module']}")
```

##### `validate_action_args(action_info: Dict, args: Dict) -> Dict[str, Any]`

Validate action arguments.

**Parameters**:
- `action_info` (Dict): Action information
- `args` (Dict): Arguments to validate

**Returns**:
- `Dict[str, Any]`: Validation result

**Example**:
```python
validation = action_manager.validate_action_args(action_info, args)
if not validation['valid']:
    print(f"Validation errors: {validation['errors']}")
```

##### `execute_action_logic(action_info: Dict, args: Dict) -> Any`

Execute action logic.

**Parameters**:
- `action_info` (Dict): Action information
- `args` (Dict): Action arguments

**Returns**:
- `Any`: Action result

**Example**:
```python
result = action_manager.execute_action_logic(action_info, args)
print(f"Action result: {result}")
```

##### `list_all_actions() -> Dict[str, Any]`

List all available actions.

**Returns**:
- `Dict[str, Any]`: List of actions

**Example**:
```python
actions = action_manager.list_all_actions()
for action_name, info in actions['actions'].items():
    print(f"Action: {action_name} -> Module: {info['module']}")
```

## Module System

### BaseModule

**File**: `core/modules/base_module.py`

#### Class Definition

```python
class BaseModule(ABC):
    def __init__(self, app_manager=None) -> None
```

#### Methods

##### `initialize(app_manager: AppManager) -> None`

Initialize the module with the AppManager.

**Parameters**:
- `app_manager` (AppManager): AppManager instance

**Example**:
```python
class MyModule(BaseModule):
    def initialize(self, app_manager):
        self.app_manager = app_manager
        # Initialize module-specific components
```

##### `register_routes() -> None`

Register module-specific routes with the Flask application.

**Example**:
```python
def register_routes(self):
    self._register_auth_route_helper('/userauth/my-endpoint', self.my_handler, methods=['GET', 'POST'])
```

##### `configure() -> None`

Configure module-specific settings.

**Example**:
```python
def configure(self):
    # Configure module settings
    self.settings = self.app_manager.get_config('my_module')
```

##### `dispose() -> None`

Cleanup module resources.

**Example**:
```python
def dispose(self):
    # Cleanup resources
    self._initialized = False
```

##### `declare_dependencies() -> List[str]`

Return list of module names this module depends on.

**Returns**:
- `List[str]`: List of dependency names

**Example**:
```python
def declare_dependencies(self) -> List[str]:
    return ['user_management_module', 'credit_system_module']
```

##### `is_initialized() -> bool`

Check if the module has been properly initialized.

**Returns**:
- `bool`: True if initialized

**Example**:
```python
if module.is_initialized():
    print("Module is ready")
```

##### `get_module_info() -> Dict[str, Any]`

Get information about this module.

**Returns**:
- `Dict[str, Any]`: Module metadata

**Example**:
```python
info = module.get_module_info()
print(f"Module: {info['name']}, Routes: {info['routes_count']}")
```

##### `health_check() -> Dict[str, Any]`

Perform a health check on the module.

**Returns**:
- `Dict[str, Any]`: Health status

**Example**:
```python
health = module.health_check()
print(f"Module health: {health['status']}")
```

## Configuration System

### Config

**File**: `utils/config/config.py`

#### Configuration Functions

##### `get_config_value(vault_path: str, vault_key: str, file_name: str = None, env_name: str = None, default_value: str = "") -> str`

Get configuration value with priority: Files > Vault > Environment > Default.

**Parameters**:
- `vault_path` (str): Vault secret path
- `vault_key` (str): Key within the vault secret
- `file_name` (str): Secret file name
- `env_name` (str): Environment variable name
- `default_value` (str): Default value

**Returns**:
- `str`: Configuration value

**Example**:
```python
debug_mode = get_config_value("flask-app/app", "debug", None, "FLASK_DEBUG", "False")
```

##### `get_sensitive_config_value(vault_path: str, vault_key: str, file_name: str = None, env_name: str = None, default_value: str = "") -> str`

Get sensitive configuration value with priority: Vault > Files > Environment > Default.

**Parameters**:
- `vault_path` (str): Vault secret path
- `vault_key` (str): Key within the vault secret
- `file_name` (str): Secret file name
- `env_name` (str): Environment variable name
- `default_value` (str): Default value

**Returns**:
- `str`: Configuration value

**Example**:
```python
jwt_secret = get_sensitive_config_value("flask-app/app", "secret_key", "jwt_secret_key", "JWT_SECRET_KEY", "default")
```

##### `get_file_first_config_value(file_name: str, env_name: str, default_value: str = "") -> str`

Get non-sensitive configuration value with priority: Files > Environment > Default.

**Parameters**:
- `file_name` (str): Secret file name
- `env_name` (str): Environment variable name
- `default_value` (str): Default value

**Returns**:
- `str`: Configuration value

**Example**:
```python
app_name = get_file_first_config_value("app_name", "APP_NAME", "My App")
```

#### Configuration Class

```python
class Config:
    # Debug mode
    DEBUG = get_config_value("flask-app/app", "debug", None, "FLASK_DEBUG", "False").lower() in ("true", "1")
    
    # Application Identity Configuration
    APP_ID = get_file_first_config_value("app_id", "APP_ID", "external_app_001")
    APP_NAME = get_file_first_config_value("app_name", "APP_NAME", "External Application")
    APP_VERSION = get_file_first_config_value("app_version", "APP_VERSION", "1.0.0")
    
    # Flask Configuration
    FLASK_SERVICE_NAME = get_config_value("flask-app/app", "service_name", "flask_service_name", "FLASK_SERVICE_NAME", "flask")
    FLASK_PORT = int(get_config_value("flask-app/app", "port", "flask_port", "FLASK_PORT", "5000"))
    
    # MongoDB Configuration
    MONGODB_SERVICE_NAME = get_config_value("flask-app/mongodb", "service_name", "mongodb_service_name", "MONGODB_SERVICE_NAME", "mongodb")
    MONGODB_ROOT_USER = get_config_value("flask-app/mongodb", "root_user", "mongodb_root_user", "MONGODB_ROOT_USER", "root")
    MONGODB_ROOT_PASSWORD = get_sensitive_config_value("flask-app/mongodb", "root_password", "mongodb_root_password", "MONGODB_ROOT_PASSWORD", "rootpassword")
    
    # Redis Configuration
    REDIS_SERVICE_NAME = get_config_value("flask-app/redis", "service_name", "redis_service_name", "REDIS_SERVICE_NAME", "redis")
    REDIS_HOST = get_config_value("flask-app/redis", "host", "redis_host", "REDIS_HOST", "redis-master-master.flask-app.svc.cluster.local")
    REDIS_PORT = int(get_config_value("flask-app/redis", "port", "redis_port", "REDIS_PORT", "6379"))
    REDIS_PASSWORD = get_sensitive_config_value("flask-app/redis", "password", "redis_password", "REDIS_PASSWORD", "")
    
    # JWT Configuration
    JWT_SECRET_KEY = get_sensitive_config_value("flask-app/app", "secret_key", "jwt_secret_key", "JWT_SECRET_KEY", "your-super-secret-key-change-in-production")
    JWT_ACCESS_TOKEN_EXPIRES = int(get_file_first_config_value("jwt_access_token_expires", "JWT_ACCESS_TOKEN_EXPIRES", "3600"))
    JWT_REFRESH_TOKEN_EXPIRES = int(get_file_first_config_value("jwt_refresh_token_expires", "JWT_REFRESH_TOKEN_EXPIRES", "604800"))
    
    # Rate Limiting Configuration
    RATE_LIMIT_ENABLED = get_file_first_config_value("rate_limit_enabled", "RATE_LIMIT_ENABLED", "false").lower() == "true"
    RATE_LIMIT_IP_REQUESTS = int(get_file_first_config_value("rate_limit_ip_requests", "RATE_LIMIT_IP_REQUESTS", "100"))
    RATE_LIMIT_IP_WINDOW = int(get_file_first_config_value("rate_limit_ip_window", "RATE_LIMIT_IP_WINDOW", "60"))
    
    # WebSocket Configuration
    WS_ALLOWED_ORIGINS = get_file_first_config_value("ws_allowed_origins", "WS_ALLOWED_ORIGINS", "*").split(",")
    WS_MAX_PAYLOAD_SIZE = int(get_file_first_config_value("ws_max_payload_size", "WS_MAX_PAYLOAD_SIZE", "1048576"))
    WS_PING_TIMEOUT = int(get_file_first_config_value("ws_ping_timeout", "WS_PING_TIMEOUT", "60"))
```

## Logging System

### Custom Logging Functions

**File**: `tools/logger/custom_logging.py`

#### Functions

##### `custom_log(message: str, level: str = "DEBUG") -> None`

Log a custom message with specified level.

**Parameters**:
- `message` (str): Message to log
- `level` (str): Log level ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")

**Example**:
```python
custom_log("Application started successfully", level="INFO")
custom_log("Database connection failed", level="ERROR")
```

##### `game_play_log(message: str, action: str = None) -> None`

Log game play events.

**Parameters**:
- `message` (str): Message to log
- `action` (str): Action type

**Example**:
```python
game_play_log("User completed level 5", action="level_complete")
```

##### `function_log(message: str) -> None`

Log function calls and execution.

**Parameters**:
- `message` (str): Message to log

**Example**:
```python
function_log("Entering function process_payment")
```

##### `log_function_call(func: Callable) -> Callable`

Decorator to log function calls.

**Parameters**:
- `func` (Callable): Function to decorate

**Returns**:
- `Callable`: Decorated function

**Example**:
```python
@log_function_call
def my_function(arg1, arg2):
    return arg1 + arg2
```

## Utility Functions

### Configuration Utilities

##### `validate_critical_config() -> bool`

Validate that critical configuration values are available and secure.

**Returns**:
- `bool`: True if configuration is valid

**Example**:
```python
if not validate_critical_config():
    print("Critical configuration issues detected")
    sys.exit(1)
```

##### `get_vault_status() -> Dict[str, Any]`

Get current Vault integration status for debugging.

**Returns**:
- `Dict[str, Any]`: Vault status information

**Example**:
```python
vault_status = get_vault_status()
print(f"Vault status: {vault_status['status']}")
```

##### `get_security_status(mongodb_password=None, jwt_secret=None, redis_password=None, stripe_secret=None, stripe_webhook_secret=None) -> Dict[str, Any]`

Get security status of sensitive configuration values.

**Parameters**:
- `mongodb_password` (str): MongoDB password
- `jwt_secret` (str): JWT secret
- `redis_password` (str): Redis password
- `stripe_secret` (str): Stripe secret key
- `stripe_webhook_secret` (str): Stripe webhook secret

**Returns**:
- `Dict[str, Any]`: Security status

**Example**:
```python
security_status = get_security_status()
for item, status in security_status.items():
    print(f"{item}: {status}")
```

## Base Classes

### Abstract Base Classes

#### ABC (Abstract Base Class)

Used for creating abstract base classes that define interfaces.

**Example**:
```python
from abc import ABC, abstractmethod

class BaseModule(ABC):
    @abstractmethod
    def initialize(self, app_manager):
        pass
```

## WebSocket API

### WebSocket Events

#### Connection Events

- `connect`: Client connects to WebSocket
- `disconnect`: Client disconnects from WebSocket

#### Room Events

- `join_room`: Join a room
- `leave_room`: Leave a room
- `room_message`: Send message to room

#### Authentication Events

- `authenticate`: Authenticate WebSocket connection
- `token_refresh`: Refresh authentication token

### WebSocket Methods

##### `emit_to_room(room: str, event: str, data: Any) -> None`

Emit event to all clients in a room.

**Parameters**:
- `room` (str): Room name
- `event` (str): Event name
- `data` (Any): Event data

**Example**:
```python
ws_manager.emit_to_room("user_123", "notification", {"message": "Hello!"})
```

##### `join_room(room: str, sid: str = None) -> None`

Join a room.

**Parameters**:
- `room` (str): Room name
- `sid` (str): Session ID (optional)

**Example**:
```python
ws_manager.join_room("user_123", sid="socket_123")
```

##### `leave_room(room: str, sid: str = None) -> None`

Leave a room.

**Parameters**:
- `room` (str): Room name
- `sid` (str): Session ID (optional)

**Example**:
```python
ws_manager.leave_room("user_123", sid="socket_123")
```

##### `get_room_info(room: str) -> Dict[str, Any]`

Get room information.

**Parameters**:
- `room` (str): Room name

**Returns**:
- `Dict[str, Any]`: Room information

**Example**:
```python
room_info = ws_manager.get_room_info("user_123")
print(f"Users in room: {room_info['users']}")
```

## Health Check API

### Health Check Endpoints

#### `GET /health`

Comprehensive health check including database, Redis, and module status.

**Response**:
```json
{
    "status": "healthy|unhealthy|degraded",
    "modules_initialized": 5,
    "total_modules": 5,
    "state_manager": {
        "status": "healthy",
        "details": "State manager is functioning normally"
    }
}
```

#### `GET /modules/status`

Get status of all modules.

**Response**:
```json
{
    "total_modules": 5,
    "initialized_modules": 5,
    "modules": {
        "user_management_module": {
            "status": "healthy",
            "routes_count": 10,
            "dependencies": ["database_manager"]
        }
    }
}
```

#### `GET /modules/<module_key>/health`

Get health status of specific module.

**Parameters**:
- `module_key` (str): Module identifier

**Response**:
```json
{
    "module": "user_management_module",
    "status": "healthy",
    "details": "Module is functioning normally"
}
```

This comprehensive API reference provides detailed information about all components of the Python Base 04 framework, enabling developers to effectively use and extend the system. 