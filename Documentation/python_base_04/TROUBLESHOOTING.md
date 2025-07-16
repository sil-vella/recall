# Troubleshooting Guide - Python Base 04

## Overview

This troubleshooting guide provides solutions for common issues encountered when working with the Python Base 04 framework. It covers problems related to initialization, authentication, database connections, Redis operations, and more.

## Table of Contents

1. [Initialization Issues](#initialization-issues)
2. [Database Connection Problems](#database-connection-problems)
3. [Redis Connection Issues](#redis-connection-issues)
4. [Authentication Problems](#authentication-problems)
5. [State Management Issues](#state-management-issues)
6. [Module Registration Problems](#module-registration-problems)
7. [Rate Limiting Issues](#rate-limiting-issues)
8. [WebSocket Problems](#websocket-problems)
9. [Configuration Issues](#configuration-issues)
10. [Performance Problems](#performance-problems)
11. [Security Issues](#security-issues)
12. [Deployment Problems](#deployment-problems)
13. [Debugging Techniques](#debugging-techniques)

## Initialization Issues

### Problem: AppManager fails to initialize

**Symptoms**:
- Application fails to start
- Error messages about missing dependencies
- Managers not properly initialized

**Solutions**:

1. **Check Flask App**:
   ```python
   # Ensure Flask app is properly created
   from flask import Flask
   app = Flask(__name__)
   
   # Verify app has required attributes
   assert hasattr(app, "add_url_rule")
   ```

2. **Verify Dependencies**:
   ```bash
   # Check if all required packages are installed
   pip install -r requirements.txt
   
   # Verify imports work
   python -c "from core.managers.app_manager import AppManager; print('Import successful')"
   ```

3. **Check Configuration**:
   ```python
   # Verify configuration is loaded
   from utils.config.config import Config
   print(f"App ID: {Config.APP_ID}")
   print(f"Debug mode: {Config.DEBUG}")
   ```

4. **Initialize Step by Step**:
   ```python
   # Initialize managers individually to identify issues
   app_manager = AppManager()
   
   # Test each manager
   try:
       app_manager.services_manager.initialize_services()
       print("Services manager initialized")
   except Exception as e:
       print(f"Services manager failed: {e}")
   ```

### Problem: Module initialization fails

**Symptoms**:
- Modules not loading
- Import errors for modules
- Module dependencies not resolved

**Solutions**:

1. **Check Module Structure**:
   ```python
   # Ensure module follows BaseModule pattern
   from core.modules.base_module import BaseModule
   
   class MyModule(BaseModule):
       def initialize(self, app_manager):
           self.app_manager = app_manager
           self._initialized = True
   ```

2. **Verify Dependencies**:
   ```python
   # Check module dependencies
   def declare_dependencies(self) -> List[str]:
       return ['user_management_module']  # List actual dependencies
   ```

3. **Check Module Registration**:
   ```python
   # Verify module is discovered
   module_manager = app_manager.module_manager
   modules = module_manager.get_all_modules()
   print(f"Registered modules: {list(modules.keys())}")
   ```

## Database Connection Problems

### Problem: Database connection fails

**Symptoms**:
- Connection timeout errors
- Authentication failures
- Connection pool exhaustion

**Solutions**:

1. **Check Connection Parameters**:
   ```python
   # Verify database configuration
   from utils.config.config import Config
   print(f"MongoDB URI: {Config.MONGODB_URI}")
   print(f"MongoDB User: {Config.MONGODB_ROOT_USER}")
   print(f"MongoDB Port: {Config.MONGODB_PORT}")
   ```

2. **Test Database Connectivity**:
   ```python
   # Test connection directly
   from pymongo import MongoClient
   
   try:
       client = MongoClient(Config.MONGODB_URI)
       client.admin.command('ping')
       print("Database connection successful")
   except Exception as e:
       print(f"Database connection failed: {e}")
   ```

3. **Check Connection Pool**:
   ```python
   # Monitor connection pool status
   db_manager = app_manager.get_db_manager()
   pool_status = db_manager.get_connection_pool_status()
   print(f"Active connections: {pool_status['active_connections']}")
   print(f"Available connections: {pool_status['available_connections']}")
   ```

4. **Reset Connection Pool**:
   ```python
   # Force connection pool reset
   db_manager = app_manager.get_db_manager()
   db_manager.reset_connection_pool()
   ```

### Problem: Database queries timeout

**Symptoms**:
- Slow query execution
- Timeout errors
- High response times

**Solutions**:

1. **Optimize Query Timeout**:
   ```python
   # Increase timeout for long-running queries
   db_manager = app_manager.get_db_manager()
   db_manager.set_query_timeout(60)  # 60 seconds
   ```

2. **Check Query Performance**:
   ```python
   # Monitor query execution time
   import time
   
   start_time = time.time()
   result = db_manager.execute_query("SELECT * FROM large_table")
   execution_time = time.time() - start_time
   print(f"Query execution time: {execution_time} seconds")
   ```

3. **Use Connection Pooling**:
   ```python
   # Ensure proper connection pooling
   db_manager = app_manager.get_db_manager(role="read_write")
   pool_status = db_manager.get_connection_pool_status()
   ```

## Redis Connection Issues

### Problem: Redis connection fails

**Symptoms**:
- Redis connection errors
- Cache operations failing
- Session data not persisting

**Solutions**:

1. **Check Redis Configuration**:
   ```python
   # Verify Redis settings
   from utils.config.config import Config
   print(f"Redis Host: {Config.REDIS_HOST}")
   print(f"Redis Port: {Config.REDIS_PORT}")
   print(f"Redis Password: {'Set' if Config.REDIS_PASSWORD else 'Not set'}")
   ```

2. **Test Redis Connectivity**:
   ```python
   # Test Redis connection
   redis_manager = app_manager.get_redis_manager()
   
   if redis_manager.ping():
       print("Redis connection successful")
   else:
       print("Redis connection failed")
   ```

3. **Check Redis Health**:
   ```python
   # Get Redis health status
   health = redis_manager.health_check()
   print(f"Redis health: {health['status']}")
   print(f"Memory usage: {health['memory_usage']}")
   ```

4. **Reset Redis Connection**:
   ```python
   # Force Redis reconnection
   redis_manager = app_manager.get_redis_manager()
   redis_manager.reconnect()
   ```

### Problem: Redis memory issues

**Symptoms**:
- Out of memory errors
- Slow Redis operations
- Cache eviction

**Solutions**:

1. **Monitor Memory Usage**:
   ```python
   # Check Redis memory usage
   redis_manager = app_manager.get_redis_manager()
   info = redis_manager.get_info()
   print(f"Used memory: {info['used_memory_human']}")
   print(f"Peak memory: {info['used_memory_peak_human']}")
   ```

2. **Set Memory Limits**:
   ```python
   # Configure Redis memory limits
   redis_manager = app_manager.get_redis_manager()
   redis_manager.set_memory_limit("512mb")
   ```

3. **Implement Cache Eviction**:
   ```python
   # Set TTL for cached data
   redis_manager.set("key", "value", ttl=3600)  # 1 hour TTL
   ```

## Authentication Problems

### Problem: JWT token validation fails

**Symptoms**:
- Authentication errors
- Token expiration issues
- Invalid token format

**Solutions**:

1. **Check JWT Configuration**:
   ```python
   # Verify JWT settings
   from utils.config.config import Config
   print(f"JWT Secret: {'Set' if Config.JWT_SECRET_KEY else 'Not set'}")
   print(f"JWT Algorithm: {Config.JWT_ALGORITHM}")
   print(f"Access Token Expires: {Config.JWT_ACCESS_TOKEN_EXPIRES}")
   ```

2. **Test Token Creation**:
   ```python
   # Test JWT token creation
   jwt_manager = app_manager.jwt_manager
   
   try:
       token = jwt_manager.create_access_token("test_user")
       print("Token creation successful")
   except Exception as e:
       print(f"Token creation failed: {e}")
   ```

3. **Validate Token**:
   ```python
   # Test token validation
   try:
       payload = jwt_manager.validate_token(token)
       print(f"Token valid for user: {payload['user_id']}")
   except Exception as e:
       print(f"Token validation failed: {e}")
   ```

4. **Check Token Blacklist**:
   ```python
   # Check if token is blacklisted
   if jwt_manager.is_token_blacklisted(token):
       print("Token is blacklisted")
   ```

### Problem: API key authentication fails

**Symptoms**:
- API key validation errors
- Permission denied errors
- Invalid API key format

**Solutions**:

1. **Verify API Key Format**:
   ```python
   # Check API key format
   api_key_manager = app_manager.api_key_manager
   
   # Generate test API key
   test_key = api_key_manager.generate_api_key("test_user", ["read"])
   print(f"Generated API key: {test_key}")
   ```

2. **Test API Key Validation**:
   ```python
   # Test API key validation
   try:
       key_info = api_key_manager.validate_api_key(api_key)
       print(f"API key valid for user: {key_info['user_id']}")
       print(f"Permissions: {key_info['permissions']}")
   except Exception as e:
       print(f"API key validation failed: {e}")
   ```

3. **Check API Key Permissions**:
   ```python
   # Verify API key permissions
   key_info = api_key_manager.get_api_key_info(api_key)
   print(f"API key permissions: {key_info['permissions']}")
   ```

## State Management Issues

### Problem: State operations fail

**Symptoms**:
- State registration errors
- State updates not persisting
- State retrieval failures

**Solutions**:

1. **Check State Manager Initialization**:
   ```python
   # Verify state manager is properly initialized
   state_manager = app_manager.get_state_manager()
   
   if state_manager:
       print("State manager initialized")
   else:
       print("State manager not initialized")
   ```

2. **Test State Registration**:
   ```python
   # Test state registration
   try:
       success = state_manager.register_state(
           state_id="test_state",
           state_type=StateType.USER,
           initial_data={"test": "data"}
       )
       print(f"State registration: {'Success' if success else 'Failed'}")
   except Exception as e:
       print(f"State registration error: {e}")
   ```

3. **Check State Persistence**:
   ```python
   # Test state persistence
   state = state_manager.get_state("test_state")
   if state:
       print(f"State retrieved: {state['data']}")
   else:
       print("State not found")
   ```

4. **Monitor State Health**:
   ```python
   # Check state manager health
   health = state_manager.health_check()
   print(f"State manager health: {health['status']}")
   ```

### Problem: State transitions fail

**Symptoms**:
- Invalid transition errors
- State update failures
- Transition validation errors

**Solutions**:

1. **Check Transition Rules**:
   ```python
   # Verify transition rules
   state = state_manager.get_state("test_state")
   if state:
       print(f"Current state: {state['data']}")
       print(f"Allowed transitions: {state.get('allowed_transitions', [])}")
   ```

2. **Validate Transitions**:
   ```python
   # Test state transition
   try:
       success = state_manager.update_state(
           state_id="test_state",
           new_data={"updated": "data"},
           transition=StateTransition.UPDATE
       )
       print(f"State transition: {'Success' if success else 'Failed'}")
   except Exception as e:
       print(f"State transition error: {e}")
   ```

## Module Registration Problems

### Problem: Modules not loading

**Symptoms**:
- Modules not discovered
- Import errors
- Module initialization failures

**Solutions**:

1. **Check Module Discovery**:
   ```python
   # Verify module discovery
   module_manager = app_manager.module_manager
   modules = module_manager.get_all_modules()
   print(f"Discovered modules: {list(modules.keys())}")
   ```

2. **Check Module Dependencies**:
   ```python
   # Verify module dependencies
   for module_name, module in modules.items():
       dependencies = module.declare_dependencies()
       print(f"Module {module_name} dependencies: {dependencies}")
   ```

3. **Test Module Initialization**:
   ```python
   # Test individual module initialization
   for module_name, module in modules.items():
       try:
           module.initialize(app_manager)
           print(f"Module {module_name} initialized successfully")
       except Exception as e:
           print(f"Module {module_name} initialization failed: {e}")
   ```

4. **Check Module Health**:
   ```python
   # Check module health
   for module_name, module in modules.items():
       health = module.health_check()
       print(f"Module {module_name} health: {health['status']}")
   ```

## Rate Limiting Issues

### Problem: Rate limiting not working

**Symptoms**:
- Rate limits not enforced
- Incorrect rate limit calculations
- Rate limit bypass

**Solutions**:

1. **Check Rate Limiter Configuration**:
   ```python
   # Verify rate limiter settings
   from utils.config.config import Config
   print(f"Rate limiting enabled: {Config.RATE_LIMIT_ENABLED}")
   print(f"IP requests limit: {Config.RATE_LIMIT_IP_REQUESTS}")
   print(f"IP window: {Config.RATE_LIMIT_IP_WINDOW}")
   ```

2. **Test Rate Limiting**:
   ```python
   # Test rate limiting functionality
   rate_limiter = app_manager.rate_limiter_manager
   
   result = rate_limiter.check_rate_limit(['ip'])
   print(f"Rate limit check: {result}")
   ```

3. **Check Rate Limit Info**:
   ```python
   # Get rate limit information
   info = rate_limiter.get_rate_limit_info("192.168.1.1", "ip")
   print(f"Remaining requests: {info['remaining']}")
   print(f"Reset time: {info['reset_time']}")
   ```

4. **Reset Rate Limits**:
   ```python
   # Reset rate limits for testing
   rate_limiter.reset_rate_limit("192.168.1.1", "ip")
   ```

### Problem: Rate limiting too aggressive

**Symptoms**:
- Legitimate requests blocked
- False positive rate limiting
- Inconsistent rate limiting

**Solutions**:

1. **Adjust Rate Limit Settings**:
   ```python
   # Increase rate limits
   # Update configuration
   RATE_LIMIT_IP_REQUESTS = 200  # Increase from 100
   RATE_LIMIT_IP_WINDOW = 60     # Keep 60 seconds
   ```

2. **Whitelist IPs**:
   ```python
   # Add IP to whitelist
   rate_limiter.whitelist_ip("192.168.1.100")
   ```

3. **Check Rate Limit Headers**:
   ```python
   # Verify rate limit headers in response
   response = requests.get("http://localhost:5001/health")
   print(f"Rate limit headers: {dict(response.headers)}")
   ```

## WebSocket Problems

### Problem: WebSocket connections fail

**Symptoms**:
- WebSocket connection errors
- Authentication failures
- Message delivery issues

**Solutions**:

1. **Check WebSocket Configuration**:
   ```python
   # Verify WebSocket settings
   from utils.config.config import Config
   print(f"WebSocket allowed origins: {Config.WS_ALLOWED_ORIGINS}")
   print(f"WebSocket max payload: {Config.WS_MAX_PAYLOAD_SIZE}")
   ```

2. **Test WebSocket Connection**:
   ```python
   # Test WebSocket connectivity
   ws_manager = app_manager.get_websocket_manager()
   
   if ws_manager:
       print("WebSocket manager initialized")
   else:
       print("WebSocket manager not available")
   ```

3. **Check WebSocket Health**:
   ```python
   # Check WebSocket health
   health = ws_manager.health_check()
   print(f"WebSocket health: {health['status']}")
   ```

4. **Test Room Operations**:
   ```python
   # Test room operations
   ws_manager.join_room("test_room", "test_socket")
   ws_manager.emit_to_room("test_room", "test_event", {"message": "test"})
   ```

### Problem: WebSocket authentication fails

**Symptoms**:
- WebSocket authentication errors
- Token validation failures
- Access denied errors

**Solutions**:

1. **Check JWT Integration**:
   ```python
   # Verify JWT manager is set
   ws_manager = app_manager.get_websocket_manager()
   jwt_manager = ws_manager.get_jwt_manager()
   
   if jwt_manager:
       print("JWT manager integrated with WebSocket")
   ```

2. **Test WebSocket Authentication**:
   ```python
   # Test WebSocket authentication
   token = jwt_manager.create_access_token("test_user")
   # Use token in WebSocket connection
   ```

## Configuration Issues

### Problem: Configuration not loading

**Symptoms**:
- Configuration values not set
- Default values being used
- Environment variables not read

**Solutions**:

1. **Check Environment Variables**:
   ```python
   # Verify environment variables
   import os
   print(f"FLASK_ENV: {os.getenv('FLASK_ENV')}")
   print(f"MONGODB_URI: {os.getenv('MONGODB_URI')}")
   print(f"REDIS_HOST: {os.getenv('REDIS_HOST')}")
   ```

2. **Test Configuration Loading**:
   ```python
   # Test configuration loading
   from utils.config.config import Config
   print(f"App ID: {Config.APP_ID}")
   print(f"Debug mode: {Config.DEBUG}")
   print(f"Database URI: {Config.MONGODB_URI}")
   ```

3. **Check Secret Files**:
   ```python
   # Verify secret files exist
   import os
   secret_files = [
       "/run/secrets/jwt_secret_key",
       "/app/secrets/mongodb_root_password",
       "./secrets/redis_password"
   ]
   
   for file_path in secret_files:
       if os.path.exists(file_path):
           print(f"Secret file exists: {file_path}")
       else:
           print(f"Secret file missing: {file_path}")
   ```

4. **Test Vault Integration**:
   ```python
   # Test Vault connection
   from utils.config.config import get_vault_status
   vault_status = get_vault_status()
   print(f"Vault status: {vault_status['status']}")
   ```

### Problem: Sensitive configuration exposed

**Symptoms**:
- Secrets in logs
- Configuration values in error messages
- Sensitive data in responses

**Solutions**:

1. **Check Configuration Security**:
   ```python
   # Verify sensitive configuration handling
   from utils.config.config import get_security_status
   security_status = get_security_status()
   
   for item, status in security_status.items():
       if status != "secure":
           print(f"Security issue: {item} - {status}")
   ```

2. **Validate Critical Configuration**:
   ```python
   # Validate critical configuration
   from utils.config.config import validate_critical_config
   if not validate_critical_config():
       print("Critical configuration issues detected")
   ```

## Performance Problems

### Problem: Slow application response

**Symptoms**:
- High response times
- Timeout errors
- Resource exhaustion

**Solutions**:

1. **Monitor Performance Metrics**:
   ```python
   # Check application metrics
   from core.monitoring.metrics_collector import metrics_collector
   metrics = metrics_collector.get_metrics()
   print(f"Request rate: {metrics['request_rate']}")
   print(f"Response time: {metrics['response_time']}")
   ```

2. **Check Database Performance**:
   ```python
   # Monitor database performance
   db_manager = app_manager.get_db_manager()
   pool_status = db_manager.get_connection_pool_status()
   print(f"Database connections: {pool_status['active_connections']}")
   ```

3. **Check Redis Performance**:
   ```python
   # Monitor Redis performance
   redis_manager = app_manager.get_redis_manager()
   info = redis_manager.get_info()
   print(f"Redis memory usage: {info['used_memory_human']}")
   print(f"Redis hit rate: {info['keyspace_hits']}")
   ```

4. **Optimize Queries**:
   ```python
   # Use connection pooling
   db_manager = app_manager.get_db_manager(role="read_write")
   
   # Use transactions for multiple operations
   operations = [
       {"type": "insert", "table": "users", "data": {"name": "John"}},
       {"type": "update", "table": "sessions", "data": {"user_id": 123}}
   ]
   db_manager.execute_transaction(operations)
   ```

### Problem: Memory leaks

**Symptoms**:
- Increasing memory usage
- Out of memory errors
- Application crashes

**Solutions**:

1. **Monitor Memory Usage**:
   ```python
   # Check memory usage
   import psutil
   process = psutil.Process()
   print(f"Memory usage: {process.memory_info().rss / 1024 / 1024} MB")
   ```

2. **Check Connection Pools**:
   ```python
   # Monitor connection pools
   db_manager = app_manager.get_db_manager()
   pool_status = db_manager.get_connection_pool_status()
   print(f"Database pool: {pool_status}")
   
   redis_manager = app_manager.get_redis_manager()
   redis_info = redis_manager.get_info()
   print(f"Redis connections: {redis_info['connected_clients']}")
   ```

3. **Cleanup Resources**:
   ```python
   # Properly dispose of managers
   app_manager.dispose()
   ```

## Security Issues

### Problem: Authentication bypass

**Symptoms**:
- Unauthorized access
- Missing authentication checks
- Token validation failures

**Solutions**:

1. **Check Authentication Middleware**:
   ```python
   # Verify authentication is enabled
   from utils.config.config import Config
   print(f"JWT enabled: {bool(Config.JWT_SECRET_KEY)}")
   ```

2. **Test Authentication Endpoints**:
   ```python
   # Test protected endpoints
   import requests
   
   # Test without authentication
   response = requests.get("http://localhost:5001/protected-endpoint")
   print(f"Unauthorized response: {response.status_code}")
   
   # Test with authentication
   headers = {"Authorization": f"Bearer {token}"}
   response = requests.get("http://localhost:5001/protected-endpoint", headers=headers)
   print(f"Authorized response: {response.status_code}")
   ```

3. **Validate Token Security**:
   ```python
   # Check token security
   jwt_manager = app_manager.jwt_manager
   
   # Test token expiration
   token = jwt_manager.create_access_token("test_user")
   payload = jwt_manager.validate_token(token)
   print(f"Token expires: {payload.get('exp')}")
   ```

### Problem: Rate limiting bypass

**Symptoms**:
- Rate limits not enforced
- Bypass attempts successful
- Inconsistent rate limiting

**Solutions**:

1. **Test Rate Limiting**:
   ```python
   # Test rate limiting enforcement
   rate_limiter = app_manager.rate_limiter_manager
   
   # Make multiple requests
   for i in range(10):
       result = rate_limiter.check_rate_limit(['ip'])
       print(f"Request {i+1}: {result['allowed']}")
   ```

2. **Check Rate Limit Headers**:
   ```python
   # Verify rate limit headers
   response = requests.get("http://localhost:5001/health")
   headers = response.headers
   
   print(f"Rate limit headers:")
   print(f"  X-RateLimit-Limit: {headers.get('X-RateLimit-Limit')}")
   print(f"  X-RateLimit-Remaining: {headers.get('X-RateLimit-Remaining')}")
   print(f"  X-RateLimit-Reset: {headers.get('X-RateLimit-Reset')}")
   ```

## Deployment Problems

### Problem: Application fails to start

**Symptoms**:
- Container startup failures
- Health check failures
- Port binding issues

**Solutions**:

1. **Check Container Logs**:
   ```bash
   # View container logs
   docker logs <container-name>
   
   # View Kubernetes pod logs
   kubectl logs <pod-name> -n <namespace>
   ```

2. **Check Health Endpoint**:
   ```bash
   # Test health endpoint
   curl -f http://localhost:5001/health
   
   # Check detailed health
   curl http://localhost:5001/health | jq
   ```

3. **Verify Port Binding**:
   ```bash
   # Check if port is bound
   netstat -tlnp | grep 5001
   
   # Check container port mapping
   docker port <container-name>
   ```

4. **Check Resource Limits**:
   ```bash
   # Check resource usage
   docker stats <container-name>
   
   # Check Kubernetes resource limits
   kubectl describe pod <pod-name> -n <namespace>
   ```

### Problem: Database connection in container

**Symptoms**:
- Database connection timeouts
- Network connectivity issues
- Service discovery problems

**Solutions**:

1. **Check Network Connectivity**:
   ```bash
   # Test network connectivity from container
   docker exec <container-name> ping <database-host>
   
   # Test port connectivity
   docker exec <container-name> telnet <database-host> <port>
   ```

2. **Verify Service Discovery**:
   ```bash
   # Check DNS resolution
   docker exec <container-name> nslookup <service-name>
   
   # Check Kubernetes service
   kubectl get svc -n <namespace>
   ```

3. **Check Environment Variables**:
   ```bash
   # Verify environment variables in container
   docker exec <container-name> env | grep -E "(MONGODB|REDIS|JWT)"
   ```

## Debugging Techniques

### 1. Enable Debug Logging

```python
# Enable detailed logging
import logging
logging.basicConfig(level=logging.DEBUG)

# Enable custom logging
from tools.logger.custom_logging import custom_log
custom_log("Debug message", level="DEBUG")
```

### 2. Use Health Checks

```python
# Check application health
response = requests.get("http://localhost:5001/health")
health_data = response.json()
print(f"Application health: {health_data['status']}")

# Check module health
response = requests.get("http://localhost:5001/modules/status")
modules_data = response.json()
for module, info in modules_data['modules'].items():
    print(f"Module {module}: {info['status']}")
```

### 3. Monitor Metrics

```python
# Get application metrics
response = requests.get("http://localhost:5001/metrics")
print(response.text)
```

### 4. Use Interactive Debugging

```python
# Use Python debugger
import pdb

def debug_function():
    pdb.set_trace()  # Breakpoint
    # Your code here
    pass
```

### 5. Check System Resources

```bash
# Monitor system resources
top
htop
free -h
df -h

# Monitor application resources
ps aux | grep python
lsof -i :5001
```

### 6. Use Application Logs

```bash
# View application logs
tail -f logs/server.log
tail -f logs/function.log
tail -f logs/game_play.log

# Search for errors
grep -i error logs/server.log
grep -i exception logs/server.log
```

### 7. Test Individual Components

```python
# Test individual managers
def test_managers():
    app_manager = AppManager()
    
    # Test each manager
    managers = [
        ('Database', app_manager.get_db_manager()),
        ('Redis', app_manager.get_redis_manager()),
        ('State', app_manager.get_state_manager()),
        ('JWT', app_manager.jwt_manager),
    ]
    
    for name, manager in managers:
        try:
            if hasattr(manager, 'health_check'):
                health = manager.health_check()
                print(f"{name} manager: {health['status']}")
            else:
                print(f"{name} manager: No health check")
        except Exception as e:
            print(f"{name} manager: Error - {e}")
```

This comprehensive troubleshooting guide provides solutions for the most common issues encountered when working with the Python Base 04 framework. Use these techniques to diagnose and resolve problems quickly and effectively. 