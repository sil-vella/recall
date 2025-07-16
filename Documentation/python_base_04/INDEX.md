# Documentation Index - Python Base 04

## Overview

This index provides a comprehensive guide to all documentation files and components in the Python Base 04 framework. Use this index to quickly locate specific information about any aspect of the system.

## Documentation Files

### Core Documentation

- **[README.md](README.md)** - Main project overview and getting started guide
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Detailed architecture documentation
- **[MANAGERS.md](MANAGERS.md)** - Comprehensive manager documentation
- **[API_REFERENCE.md](API_REFERENCE.md)** - Complete API reference
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Deployment instructions and configurations
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Troubleshooting guide and solutions

## Core Components

### Managers

#### Primary Managers
- **AppManager** - Application orchestrator and lifecycle manager
  - File: `core/managers/app_manager.py`
  - Documentation: [MANAGERS.md#appmanager](MANAGERS.md#1-appmanager)
  - API Reference: [API_REFERENCE.md#appmanager](API_REFERENCE.md#appmanager)

- **StateManager** - Centralized state management system
  - File: `core/managers/state_manager.py`
  - Documentation: [MANAGERS.md#statemanager](MANAGERS.md#2-statemanager)
  - API Reference: [API_REFERENCE.md#statemanager](API_REFERENCE.md#statemanager)

- **DatabaseManager** - Database operations and connection management
  - File: `core/managers/database_manager.py`
  - Documentation: [MANAGERS.md#databasemanager](MANAGERS.md#3-databasemanager)
  - API Reference: [API_REFERENCE.md#databasemanager](API_REFERENCE.md#databasemanager)

- **RedisManager** - Redis operations and caching management
  - File: `core/managers/redis_manager.py`
  - Documentation: [MANAGERS.md#redismanager](MANAGERS.md#4-redismanager)
  - API Reference: [API_REFERENCE.md#redismanager](API_REFERENCE.md#redismanager)

#### Authentication Managers
- **JWTManager** - JWT token management and authentication
  - File: `core/managers/jwt_manager.py`
  - Documentation: [MANAGERS.md#jwtmanager](MANAGERS.md#5-jwtmanager)
  - API Reference: [API_REFERENCE.md#jwtmanager](API_REFERENCE.md#jwtmanager)

- **ApiKeyManager** - API key management and authentication
  - File: `core/managers/api_key_manager.py`
  - Documentation: [MANAGERS.md#apikeymanager](MANAGERS.md#6-apikeymanager)
  - API Reference: [API_REFERENCE.md#apikeymanager](API_REFERENCE.md#apikeymanager)

#### Security Managers
- **VaultManager** - HashiCorp Vault integration for secret management
  - File: `core/managers/vault_manager.py`
  - Documentation: [MANAGERS.md#vaultmanager](MANAGERS.md#7-vaultmanager)
  - API Reference: [API_REFERENCE.md#vaultmanager](API_REFERENCE.md#vaultmanager)

- **RateLimiterManager** - Multi-level rate limiting and protection
  - File: `core/managers/rate_limiter_manager.py`
  - Documentation: [MANAGERS.md#ratelimitermanager](MANAGERS.md#8-ratelimitermanager)
  - API Reference: [API_REFERENCE.md#ratelimitermanager](API_REFERENCE.md#ratelimitermanager)

#### Specialized Managers
- **ActionDiscoveryManager** - Dynamic action registration and execution
  - File: `core/managers/action_discovery_manager.py`
  - Documentation: [MANAGERS.md#actiondiscoverymanager](MANAGERS.md#9-actiondiscoverymanager)
  - API Reference: [API_REFERENCE.md#actiondiscoverymanager](API_REFERENCE.md#actiondiscoverymanager)

- **WebSocketManager** - WebSocket management and real-time communication
  - File: `core/managers/websockets/websocket_manager.py`
  - Documentation: [MANAGERS.md#websocketmanager](MANAGERS.md#10-websocketmanager)
  - API Reference: [API_REFERENCE.md#websocket-api](API_REFERENCE.md#websocket-api)

### Module System

#### Base Module
- **BaseModule** - Abstract base class for all modules
  - File: `core/modules/base_module.py`
  - Documentation: [API_REFERENCE.md#module-system](API_REFERENCE.md#module-system)
  - API Reference: [API_REFERENCE.md#basemodule](API_REFERENCE.md#basemodule)

#### Feature Modules
- **UserManagementModule** - User management functionality
  - Directory: `core/modules/user_management_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

- **CreditSystemModule** - Credit system functionality
  - Directory: `core/modules/credit_system_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

- **WalletModule** - Wallet functionality
  - Directory: `core/modules/wallet_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

- **TransactionsModule** - Transaction handling
  - Directory: `core/modules/transactions_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

- **CommunicationsModule** - Communication features
  - Directory: `core/modules/communications_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

- **StripeModule** - Stripe integration
  - Directory: `core/modules/stripe_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

- **SystemActionsModule** - System actions
  - Directory: `core/modules/system_actions_module/`
  - Documentation: [MANAGERS.md#module-system](MANAGERS.md#module-system)

### Configuration System

#### Configuration Management
- **Config** - Main configuration class
  - File: `utils/config/config.py`
  - Documentation: [API_REFERENCE.md#configuration-system](API_REFERENCE.md#configuration-system)
  - API Reference: [API_REFERENCE.md#config](API_REFERENCE.md#config)

#### Configuration Functions
- **get_config_value()** - Get configuration with priority
  - Documentation: [API_REFERENCE.md#get_config_value](API_REFERENCE.md#get_config_value)

- **get_sensitive_config_value()** - Get sensitive configuration
  - Documentation: [API_REFERENCE.md#get_sensitive_config_value](API_REFERENCE.md#get_sensitive_config_value)

- **get_file_first_config_value()** - Get file-first configuration
  - Documentation: [API_REFERENCE.md#get_file_first_config_value](API_REFERENCE.md#get_file_first_config_value)

### Logging System

#### Logging Functions
- **custom_log()** - Main logging function
  - File: `tools/logger/custom_logging.py`
  - Documentation: [API_REFERENCE.md#custom_log](API_REFERENCE.md#custom_log)

- **game_play_log()** - Game play event logging
  - File: `tools/logger/custom_logging.py`
  - Documentation: [API_REFERENCE.md#game_play_log](API_REFERENCE.md#game_play_log)

- **function_log()** - Function call logging
  - File: `tools/logger/custom_logging.py`
  - Documentation: [API_REFERENCE.md#function_log](API_REFERENCE.md#function_log)

- **log_function_call()** - Function call decorator
  - File: `tools/logger/custom_logging.py`
  - Documentation: [API_REFERENCE.md#log_function_call](API_REFERENCE.md#log_function_call)

## API Endpoints

### Health and Status
- **GET /health** - Application health check
  - Documentation: [API_REFERENCE.md#health-check-api](API_REFERENCE.md#health-check-api)
  - Response: Health status with all component statuses

- **GET /modules/status** - Module status
  - Documentation: [API_REFERENCE.md#health-check-api](API_REFERENCE.md#health-check-api)
  - Response: Status of all modules

- **GET /modules/<module_key>/health** - Specific module health
  - Documentation: [API_REFERENCE.md#health-check-api](API_REFERENCE.md#health-check-api)
  - Response: Health status of specific module

### Action Discovery
- **GET /actions** - List all internal actions
  - Documentation: [API_REFERENCE.md#action-discovery](API_REFERENCE.md#action-discovery)
  - Response: List of available actions

- **GET /api-auth/actions** - List all authenticated actions
  - Documentation: [API_REFERENCE.md#action-discovery](API_REFERENCE.md#action-discovery)
  - Response: List of available authenticated actions

### Action Execution
- **GET/POST /actions/<action_name>/<args>** - Execute internal action
  - Documentation: [API_REFERENCE.md#action-execution](API_REFERENCE.md#action-execution)
  - Parameters: action_name, args, request data

- **GET/POST /api-auth/actions/<action_name>/<args>** - Execute authenticated action
  - Documentation: [API_REFERENCE.md#action-execution](API_REFERENCE.md#action-execution)
  - Parameters: action_name, args, request data, authentication

## Development Workflow

### Getting Started
1. **Installation** - [README.md#installation](README.md#installation)
2. **Configuration** - [README.md#configuration](README.md#configuration)
3. **Running the Application** - [README.md#running-the-application](README.md#running-the-application)

### Development Guidelines
1. **Code Style** - [README.md#code-style](README.md#code-style)
2. **Module Development** - [README.md#module-development](README.md#module-development)
3. **State Management** - [README.md#state-management](README.md#state-management)
4. **Authentication** - [README.md#authentication](README.md#authentication)
5. **API Development** - [README.md#api-development](README.md#api-development)

### Testing
1. **Unit Tests** - [README.md#unit-tests](README.md#unit-tests)
2. **Integration Tests** - [README.md#integration-tests](README.md#integration-tests)
3. **API Tests** - [README.md#api-tests](README.md#api-tests)

## Deployment

### Deployment Options
1. **Local Development** - [DEPLOYMENT.md#local-development-deployment](DEPLOYMENT.md#local-development-deployment)
2. **Docker Deployment** - [DEPLOYMENT.md#docker-deployment](DEPLOYMENT.md#docker-deployment)
3. **Kubernetes Deployment** - [DEPLOYMENT.md#kubernetes-deployment](DEPLOYMENT.md#kubernetes-deployment)
4. **Production Deployment** - [DEPLOYMENT.md#production-deployment](DEPLOYMENT.md#production-deployment)

### CI/CD Pipeline
1. **GitHub Actions** - [DEPLOYMENT.md#github-actions-workflow](DEPLOYMENT.md#github-actions-workflow)
2. **GitLab CI/CD** - [DEPLOYMENT.md#gitlab-cicd-pipeline](DEPLOYMENT.md#gitlab-cicd-pipeline)

### Monitoring
1. **Prometheus Configuration** - [DEPLOYMENT.md#prometheus-configuration](DEPLOYMENT.md#prometheus-configuration)
2. **Grafana Dashboard** - [DEPLOYMENT.md#grafana-dashboard](DEPLOYMENT.md#grafana-dashboard)
3. **Health Checks** - [DEPLOYMENT.md#health-check-endpoints](DEPLOYMENT.md#health-check-endpoints)

## Architecture

### Manager Pattern
- **Manager Dependencies** - [MANAGERS.md#manager-dependencies](MANAGERS.md#manager-dependencies)
- **Manager Initialization Order** - [MANAGERS.md#manager-initialization-order](MANAGERS.md#manager-initialization-order)
- **Health Monitoring** - [MANAGERS.md#health-monitoring](MANAGERS.md#health-monitoring)

### Module System
- **Base Module** - [API_REFERENCE.md#basemodule](API_REFERENCE.md#basemodule)
- **Module Dependencies** - [API_REFERENCE.md#declare_dependencies](API_REFERENCE.md#declare_dependencies)
- **Module Health** - [API_REFERENCE.md#health_check](API_REFERENCE.md#health_check)

### State Management
- **State Types** - [API_REFERENCE.md#statetype](API_REFERENCE.md#statetype)
- **State Transitions** - [API_REFERENCE.md#statetransition](API_REFERENCE.md#statetransition)
- **State Operations** - [API_REFERENCE.md#state-operations](API_REFERENCE.md#state-operations)

## Security

### Authentication
1. **JWT Authentication** - [MANAGERS.md#jwtmanager](MANAGERS.md#5-jwtmanager)
2. **API Key Authentication** - [MANAGERS.md#apikeymanager](MANAGERS.md#6-apikeymanager)
3. **WebSocket Authentication** - [MANAGERS.md#websocketmanager](MANAGERS.md#10-websocketmanager)

### Rate Limiting
1. **IP-based Limiting** - [MANAGERS.md#ratelimitermanager](MANAGERS.md#8-ratelimitermanager)
2. **User-based Limiting** - [MANAGERS.md#ratelimitermanager](MANAGERS.md#8-ratelimitermanager)
3. **API Key-based Limiting** - [MANAGERS.md#ratelimitermanager](MANAGERS.md#8-ratelimitermanager)

### Secret Management
1. **Vault Integration** - [MANAGERS.md#vaultmanager](MANAGERS.md#7-vaultmanager)
2. **File-based Secrets** - [API_REFERENCE.md#get_sensitive_config_value](API_REFERENCE.md#get_sensitive_config_value)
3. **Environment Variables** - [API_REFERENCE.md#get_config_value](API_REFERENCE.md#get_config_value)

## Troubleshooting

### Common Issues
1. **Initialization Issues** - [TROUBLESHOOTING.md#initialization-issues](TROUBLESHOOTING.md#initialization-issues)
2. **Database Connection Problems** - [TROUBLESHOOTING.md#database-connection-problems](TROUBLESHOOTING.md#database-connection-problems)
3. **Redis Connection Issues** - [TROUBLESHOOTING.md#redis-connection-issues](TROUBLESHOOTING.md#redis-connection-issues)
4. **Authentication Problems** - [TROUBLESHOOTING.md#authentication-problems](TROUBLESHOOTING.md#authentication-problems)
5. **State Management Issues** - [TROUBLESHOOTING.md#state-management-issues](TROUBLESHOOTING.md#state-management-issues)

### Debugging Techniques
1. **Enable Debug Logging** - [TROUBLESHOOTING.md#enable-debug-logging](TROUBLESHOOTING.md#enable-debug-logging)
2. **Use Health Checks** - [TROUBLESHOOTING.md#use-health-checks](TROUBLESHOOTING.md#use-health-checks)
3. **Monitor Metrics** - [TROUBLESHOOTING.md#monitor-metrics](TROUBLESHOOTING.md#monitor-metrics)
4. **Interactive Debugging** - [TROUBLESHOOTING.md#use-interactive-debugging](TROUBLESHOOTING.md#use-interactive-debugging)

## Performance

### Optimization
1. **Connection Pooling** - [DEPLOYMENT.md#connection-pooling](DEPLOYMENT.md#connection-pooling)
2. **Caching Strategy** - [MANAGERS.md#caching-strategy](MANAGERS.md#caching-strategy)
3. **Rate Limiting** - [MANAGERS.md#rate-limiting](MANAGERS.md#rate-limiting)

### Monitoring
1. **Prometheus Metrics** - [DEPLOYMENT.md#prometheus-configuration](DEPLOYMENT.md#prometheus-configuration)
2. **Health Checks** - [API_REFERENCE.md#health-check-api](API_REFERENCE.md#health-check-api)
3. **Performance Metrics** - [TROUBLESHOOTING.md#monitor-performance-metrics](TROUBLESHOOTING.md#monitor-performance-metrics)

## Common Patterns

### Manager Usage
```python
# Get manager instances
app_manager = AppManager()
state_manager = app_manager.get_state_manager()
db_manager = app_manager.get_db_manager()
redis_manager = app_manager.get_redis_manager()

# Initialize application
app_manager.initialize(app)
```

### Module Development
```python
# Create new module
class MyModule(BaseModule):
    def initialize(self, app_manager):
        self.app_manager = app_manager
        self._initialized = True
    
    def register_routes(self):
        self._register_auth_route_helper('/my-endpoint', self.my_handler)
    
    def health_check(self):
        return {'status': 'healthy', 'module': self.module_name}
```

### State Management
```python
# Register state
state_manager.register_state(
    state_id="user_123_session",
    state_type=StateType.SESSION,
    initial_data={"user_id": "123"}
)

# Update state
state_manager.update_state(
    state_id="user_123_session",
    new_data={"last_activity": "2024-01-01T11:00:00Z"},
    transition=StateTransition.UPDATE
)
```

### Authentication
```python
# JWT authentication
jwt_manager = app_manager.jwt_manager
token = jwt_manager.create_access_token("user_123")
payload = jwt_manager.validate_token(token)

# API key authentication
api_key_manager = app_manager.api_key_manager
key_info = api_key_manager.validate_api_key(api_key)
```

### Configuration
```python
# Get configuration values
from utils.config.config import Config
debug_mode = Config.DEBUG
db_uri = Config.MONGODB_URI
jwt_secret = Config.JWT_SECRET_KEY
```

### Logging
```python
# Use custom logging
from tools.logger.custom_logging import custom_log
custom_log("Application started", level="INFO")
custom_log("Error occurred", level="ERROR")
```

## Support Resources

### Documentation Files
- **README.md** - Start here for project overview
- **ARCHITECTURE.md** - Understand the system architecture
- **MANAGERS.md** - Learn about all managers
- **API_REFERENCE.md** - Complete API documentation
- **DEPLOYMENT.md** - Deployment instructions
- **TROUBLESHOOTING.md** - Problem-solving guide

### Key Components
- **AppManager** - Main application orchestrator
- **StateManager** - State management system
- **DatabaseManager** - Database operations
- **RedisManager** - Caching and sessions
- **JWTManager** - Authentication
- **VaultManager** - Secret management
- **RateLimiterManager** - Rate limiting
- **ActionDiscoveryManager** - Dynamic actions
- **WebSocketManager** - Real-time communication

### Quick Reference
- **Health Check**: `GET /health`
- **Module Status**: `GET /modules/status`
- **Action List**: `GET /actions`
- **Metrics**: `GET /metrics`
- **Configuration**: `utils/config/config.py`
- **Logging**: `tools/logger/custom_logging.py`

This comprehensive index provides quick access to all documentation and components in the Python Base 04 framework. Use this index to navigate the documentation efficiently and find the information you need quickly. 