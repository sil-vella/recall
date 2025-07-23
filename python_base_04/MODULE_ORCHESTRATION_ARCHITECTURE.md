# Module Orchestration Architecture

## Overview

This document details the module orchestration architecture that provides complete decoupling between business logic modules and system integration, while maintaining a clean separation of concerns through the hook system and orchestrator pattern.

## Core Architecture Principles

### 1. Complete Decoupling from Global Config

**Problem**: Modules were tightly coupled to the global `Config` class, making them dependent on system-level configuration management.

**Solution**: Each module now has its own independent secret reading logic with a fallback chain:

```
Module Secrets Directory → Global Secrets → Kubernetes Secrets → Local Dev Secrets → Environment Variables → Defaults
```

**Implementation**:
```python
# Module-specific secrets directory
system/modules/user_management_module/secrets/
system/modules/credit_system_module/secrets/

# Independent secret reading in modules
def _read_module_secret(self, secret_name: str) -> Optional[str]:
    # Try module-specific secrets first
    # Fall back through the chain
    # Return None if not found
```

### 2. Module-Orchestrator Pattern

**Pattern**: Every module has a corresponding orchestrator that handles system integration.

```
Module (Business Logic) ←→ Orchestrator (System Integration) ←→ System Managers
```

**Responsibilities**:
- **Module**: Pure business logic, independent of system dependencies
- **Orchestrator**: System integration, lifecycle management, request forwarding
- **System Managers**: Database, Redis, JWT, etc.

### 3. Manager Storage Pattern

**Pattern**: Orchestrators store commonly used managers as instance variables during initialization for consistent access.

```python
class ModuleOrchestratorBase:
    def __init__(self, manager_initializer):
        self.manager_initializer = manager_initializer
        self._store_common_managers()
    
    def _store_common_managers(self):
        """Store commonly used managers as instance variables."""
        self.db_manager = self.manager_initializer.get_manager('db_manager')
        self.jwt_manager = self.manager_initializer.get_manager('jwt_manager')
        self.hooks_manager = self.manager_initializer.get_manager('hooks_manager')
        # Add other managers as needed
```

## Hook System Architecture

### 1. Hook Registration Pattern

**How it works**:
1. Module declares what hooks it needs via `get_hooks_needed()`
2. Orchestrator registers hooks with the system during initialization
3. System triggers hooks when events occur
4. Orchestrator forwards hook events to module for processing

**Example**:
```python
# Module declares hooks needed
def get_hooks_needed(self) -> List[Dict[str, Any]]:
    return [
        {
            'event': 'user_created',
            'priority': 10,
            'context': 'user_management',
            'description': 'Process user creation in user management'
        }
    ]

# Orchestrator registers hooks
def _register_hooks(self):
    hooks_needed = self.module.get_hooks_needed()
    
    for hook_info in hooks_needed:
        self.hooks_manager.register_hook(
            event=hook_info['event'],
            callback=self._handle_hook_event,
            priority=hook_info.get('priority', 10),
            context=hook_info.get('context', 'user_management')
        )
```

### 2. Hook Callback Registration

**Pattern**: Orchestrators register callback functions with the hooks manager to handle system events.

```python
# Orchestrator registers callback
def _register_route_callback(self):
    self.hooks_manager.register_hook_callback(
        "register_routes",
        self.register_routes_callback,
        priority=10,
        context="user_management_orchestrator"
    )

# Callback handles the event
def register_routes_callback(self, data=None):
    # Register routes with Flask when hook is triggered
    routes_needed = self.module.get_routes_needed()
    # ... register routes
```

## Route Registration Architecture

### 1. Declarative Route Pattern

**How it works**:
1. Module declares routes it needs via `get_routes_needed()`
2. Orchestrator registers route callback with hooks manager
3. When `register_routes` hook is triggered, orchestrator registers routes with Flask
4. Flask route handlers in orchestrator process requests and delegate to module

**Example**:
```python
# Module declares routes
def get_routes_needed(self) -> List[Dict[str, Any]]:
    return [
        {
            'route': '/public/register',
            'methods': ['POST'],
            'handler': 'create_user',
            'description': 'Create a new user account',
            'auth_required': False
        },
        {
            'route': '/userauth/me',
            'methods': ['GET'],
            'handler': 'get_current_user',
            'description': 'Get current user information',
            'auth_required': True
        }
    ]

# Orchestrator registers routes via hook
def register_routes_callback(self, data=None):
    from flask import current_app
    
    routes_needed = self.module.get_routes_needed()
    
    for route_info in routes_needed:
        route = route_info['route']
        methods = route_info['methods']
        handler_name = route_info['handler']
        
        handler_method = getattr(self, handler_name, None)
        if handler_method:
            current_app.add_url_rule(
                route,
                f"user_management_{handler_name}",
                handler_method,
                methods=methods
            )
```

### 2. Route Handler Pattern

**Pattern**: Orchestrators contain Flask route handlers that:
1. Validate requests
2. Use stored manager instances for system operations
3. Delegate business logic to module
4. Return Flask responses

```python
# Orchestrator route handler
def create_user(self):
    """Create a new user account."""
    try:
        data = request.get_json()
        
        # Use module for business logic
        result = self.module.process_user_creation(data)
        
        if not result['success']:
            return jsonify({"success": False, "error": result['error']}), 400
        
        # Use stored database manager for persistence
        existing_user = self.db_manager.find_one("users", {"email": data.get("email")})
        if existing_user:
            return jsonify({"success": False, "error": "User already exists"}), 409
        
        # Insert user
        user_document = result['user_document']
        inserted_id = self.db_manager.insert("users", user_document)
        
        return jsonify({"success": True, "user_id": str(inserted_id)}), 201
        
    except Exception as e:
        return jsonify({"success": False, "error": "Internal server error"}), 500
```

## JWT Token Management Architecture

### 1. Token Creation Pattern

**Pattern**: JWT tokens are created with proper data dictionaries containing user information.

```python
# Correct JWT token creation
def login_user(self):
    # ... user validation ...
    
    # Generate JWT tokens with original email from login request
    access_token = self.jwt_manager.create_access_token(
        data={"user_id": str(user["_id"]), "email": data.get("email"), "username": user["username"]}
    )
    refresh_token = self.jwt_manager.create_refresh_token(
        data={"user_id": str(user["_id"]), "email": data.get("email"), "username": user["username"]}
    )
```

### 2. Token Validation Pattern

**Pattern**: JWT tokens contain original email addresses for proper validation.

```python
# JWT validation expects valid email format
def _validate_custom_claims(self, payload: Dict[str, Any]) -> bool:
    email = payload.get('email')
    if email:
        # Basic email format validation
        if '@' not in email or '.' not in email:
            return False
    return True
```

### 3. Refresh Token Pattern

**Pattern**: Refresh tokens return new access tokens as strings.

```python
# JWT manager returns string for refresh
def refresh_token(self, refresh_token: str) -> Optional[str]:
    payload = self.verify_token(refresh_token, TokenType.REFRESH)
    if payload:
        new_payload = {k: v for k, v in payload.items() 
                     if k not in ['exp', 'iat', 'type']}
        return self.create_token(new_payload, TokenType.ACCESS)
    return None

# Orchestrator handles string return
def refresh_token(self):
    new_access_token = self.jwt_manager.refresh_token(refresh_token)
    
    if new_access_token:
        return jsonify({
            "success": True,
            "message": "Token refreshed successfully",
            "access_token": new_access_token
        }), 200
```

## Module Independence Architecture

### 1. Secret Management Independence

**Before**: Modules depended on global `Config` class
```python
# OLD - Tightly coupled
from utils.config.config import Config
secret_key = Config.JWT_SECRET_KEY
```

**After**: Modules have independent secret reading
```python
# NEW - Completely decoupled
def _read_module_secret(self, secret_name: str) -> Optional[str]:
    # Try module-specific secrets first
    module_secret_path = f"system/modules/user_management_module/secrets/{secret_name}"
    if os.path.exists(module_secret_path):
        with open(module_secret_path, 'r') as f:
            return f.read().strip()
    
    # Fall back through the chain
    # ... implementation
```

### 2. System Dependency Independence

**Before**: Modules directly used system managers
```python
# OLD - Direct system dependency
from system.managers.database_manager import DatabaseManager
db_manager = DatabaseManager()
```

**After**: Modules are pure business logic, orchestrators handle system integration
```python
# NEW - Pure business logic
def process_user_creation(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
    # Only business logic, no system dependencies
    validation_result = self.validate_user_data(user_data)
    if not validation_result['success']:
        return validation_result
    
    # Return processed data for orchestrator to persist
    return {
        'success': True,
        'user_document': self._prepare_user_document(user_data)
    }
```

## Directory Structure

```
python_base_04/
├── system/
│   ├── modules/                           # Pure business logic modules
│   │   ├── user_management_module/
│   │   │   ├── user_management_main.py   # Pure business logic
│   │   │   └── secrets/                  # Module-specific secrets
│   │   └── credit_system_module/
│   │       ├── credit_system_main.py     # Pure business logic
│   │       └── secrets/                  # Module-specific secrets
│   ├── orchestration/                    # System integration
│   │   └── modules_orch/
│   │       ├── base_files/
│   │       │   └── module_orch_base.py   # Base orchestrator class
│   │       ├── user_management_orch/
│   │       │   └── user_management_orchestrator.py
│   │       └── credit_system_orch/
│   │           └── credit_system_orchestrator.py
│   └── managers/                         # System managers
│       ├── database_manager.py
│       ├── jwt_manager.py
│       └── hooks_manager.py
```

## Lifecycle Management

### 1. Initialization Flow

```
1. App starts
2. ManagerInitializer creates system managers
3. Orchestrators are created with manager_initializer
4. Orchestrator.initialize() is called
5. Module is created and initialized
6. Common managers are stored as instance variables
7. Hooks are registered with system
8. Route callbacks are registered with hooks manager
9. Orchestrator is ready
```

### 2. Request Flow

```
1. Flask receives request
2. Route handler in orchestrator is called
3. Orchestrator validates request
4. Orchestrator uses stored manager instances
5. Orchestrator calls module business logic
6. Module processes business logic (no system dependencies)
7. Orchestrator persists results using stored managers
8. Orchestrator returns Flask response
```

### 3. Hook Event Flow

```
1. System event occurs (e.g., user_created)
2. Hooks manager triggers registered hooks
3. Orchestrator._handle_hook_event() is called
4. Orchestrator forwards event to module
5. Module.process_hook_event() processes business logic
6. Module returns result
7. Orchestrator handles any system integration needed
```

## Benefits of This Architecture

### 1. Complete Decoupling
- **Modules**: Pure business logic, no system dependencies
- **Orchestrators**: Handle all system integration with stored manager instances
- **System Managers**: Reusable across all modules

### 2. Testability
- **Modules**: Can be unit tested without system dependencies
- **Orchestrators**: Can be integration tested with mocked managers
- **System**: Can be tested independently

### 3. Maintainability
- **Clear separation**: Business logic vs system integration
- **Consistent patterns**: All modules follow same architecture
- **Easy to extend**: Add new modules following established pattern
- **Manager access**: Consistent access through stored instance variables

### 4. Flexibility
- **Independent deployment**: Modules can be deployed separately
- **Technology agnostic**: Modules don't care about system technology
- **Easy to replace**: Swap orchestrators without changing modules

## Implementation Examples

### 1. User Management Module
```python
class UserManagementModule:
    def __init__(self):
        # No system dependencies
        self.secret_sources = self._get_secret_sources()
    
    def process_user_creation(self, user_data):
        # Pure business logic
        validation = self.validate_user_data(user_data)
        if not validation['success']:
            return validation
        
        # Return data for orchestrator to persist
        return {
            'success': True,
            'user_document': self._prepare_user_document(user_data)
        }
```

### 2. User Management Orchestrator
```python
class UserManagementOrchestrator(ModuleOrchestratorBase):
    def __init__(self, manager_initializer):
        super().__init__(manager_initializer)
        self.module = None
    
    def initialize(self):
        # Create module (no config needed)
        self.module = UserManagementModule()
        self.module.initialize()
        
        # Register hooks and route callbacks
        self._register_hooks()
        self._register_route_callback()
    
    def create_user(self):
        # Flask route handler
        data = request.get_json()
        result = self.module.process_user_creation(data)
        
        if result['success']:
            # Use stored database manager for persistence
            inserted_id = self.db_manager.insert("users", result['user_document'])
            return jsonify({"success": True, "user_id": str(inserted_id)}), 201
        else:
            return jsonify({"success": False, "error": result['error']}), 400
    
    def login_user(self):
        # ... user validation ...
        
        # Generate JWT tokens with original email
        access_token = self.jwt_manager.create_access_token(
            data={"user_id": str(user["_id"]), "email": data.get("email"), "username": user["username"]}
        )
        refresh_token = self.jwt_manager.create_refresh_token(
            data={"user_id": str(user["_id"]), "email": data.get("email"), "username": user["username"]}
        )
```

## Migration Guide

### From Global Config Dependencies

**Before**:
```python
from utils.config.config import Config

class UserModule:
    def __init__(self):
        self.jwt_secret = Config.JWT_SECRET_KEY
        self.db_url = Config.DATABASE_URL
```

**After**:
```python
class UserModule:
    def __init__(self):
        self.jwt_secret = self._read_module_secret('jwt_secret')
        self.db_url = self._read_module_secret('database_url')
    
    def _read_module_secret(self, secret_name: str) -> Optional[str]:
        # Independent secret reading with fallback chain
        # Module secrets → Global secrets → Environment → Defaults
```

### From Direct System Dependencies

**Before**:
```python
from system.managers.database_manager import DatabaseManager

class UserModule:
    def create_user(self, user_data):
        db_manager = DatabaseManager()
        return db_manager.insert("users", user_data)
```

**After**:
```python
class UserModule:
    def process_user_creation(self, user_data):
        # Pure business logic
        validation = self.validate_user_data(user_data)
        if not validation['success']:
            return validation
        
        return {
            'success': True,
            'user_document': self._prepare_user_document(user_data)
        }

class UserOrchestrator(ModuleOrchestratorBase):
    def create_user(self):
        data = request.get_json()
        result = self.module.process_user_creation(data)
        
        if result['success']:
            # Use stored database manager
            return self.db_manager.insert("users", result['user_document'])
```

### From get_manager() Calls

**Before**:
```python
class UserOrchestrator:
    def create_user(self):
        db_manager = self.manager_initializer.get_manager('db_manager')
        jwt_manager = self.manager_initializer.get_manager('jwt_manager')
        # ... use managers
```

**After**:
```python
class UserOrchestrator(ModuleOrchestratorBase):
    def create_user(self):
        # Use stored manager instances
        result = self.db_manager.insert("users", user_data)
        token = self.jwt_manager.create_access_token(data)
        # ... use managers
```

## Conclusion

This architecture provides complete decoupling between business logic and system integration while maintaining clean separation of concerns through the hook system and orchestrator pattern. Modules are now pure business logic utilities that can be easily tested, maintained, and deployed independently of the system infrastructure.

The hook system ensures that modules can declare their needs (routes, hooks) and orchestrators handle the system integration, creating a flexible and maintainable architecture that scales with the application's complexity.

Key improvements include:
- **Manager Storage**: Common managers stored as instance variables for consistent access
- **JWT Token Handling**: Proper data dictionary format and original email storage
- **Refresh Token Pattern**: String return values handled correctly
- **Base Orchestrator Class**: Shared functionality and patterns across all orchestrators 