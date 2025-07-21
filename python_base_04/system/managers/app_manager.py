# Plugin system removed - now using direct module management
# from core.managers.plugin_manager import PluginManager
from system.managers.service_manager import ServicesManager
from system.managers.hooks_manager import HooksManager
from system.managers.module_manager import ModuleManager
from system.managers.rate_limiter_manager import RateLimiterManager
from jinja2 import ChoiceLoader, FileSystemLoader
from tools.logger.custom_logging import custom_log, function_log, game_play_log, log_function_call
import os
from flask import request, jsonify
import time
from utils.config.config import Config
from redis.exceptions import RedisError
from system.monitoring.metrics_collector import metrics_collector
import logging
from apscheduler.schedulers.background import BackgroundScheduler
from system.managers.database_manager import DatabaseManager
from system.managers.redis_manager import RedisManager
from system.managers.state_manager import StateManager
from system.managers.user_actions_manager import UserActionsManager
from system.managers.action_discovery_manager import ActionDiscoveryManager
from system.managers.websockets.websocket_manager import WebSocketManager


class AppManager:
    def __init__(self):
        self.services_manager = ServicesManager()
        self.hooks_manager = HooksManager()
        self.module_manager = ModuleManager()  # Primary orchestrator
        self.template_dirs = []  # List to track template directories
        self.flask_app = None  # Flask app reference
        self.logger = logging.getLogger(__name__)
        self.scheduler = None
        
        # Centralized managers - single instances for all modules
        self.db_manager = None
        self.analytics_db = None
        self.admin_db = None
        self.redis_manager = None
        self.rate_limiter_manager = None
        self.state_manager = None
        self.jwt_manager = None
        self.user_actions_manager = None
        self.action_discovery_manager = None
        self._initialized = False

        custom_log("AppManager instance created.")

    def is_initialized(self):
        """Check if the AppManager is properly initialized."""
        return self._initialized

    def check_database_connection(self):
        """Check if the database connection is healthy."""
        try:
            if not self.db_manager:
                return False
            # Try to execute a simple query to check connection
            return self.db_manager.check_connection()
        except Exception as e:
            custom_log(f"Database health check failed: {e}", level="ERROR")
            return False

    def check_redis_connection(self):
        """Check if the Redis connection is healthy."""
        try:
            if not self.redis_manager:
                return False
            # Try to execute a PING command
            return self.redis_manager.ping()
        except Exception as e:
            custom_log(f"Redis health check failed: {e}", level="ERROR")
            return False

    def get_db_manager(self, role="read_write"):
        """Get the appropriate database manager instance."""
        if role == "read_write":
            return self.db_manager
        elif role == "read_only":
            return self.analytics_db
        elif role == "admin":
            return self.admin_db
        else:
            raise ValueError(f"Unknown database role: {role}")

    def get_redis_manager(self):
        """Get the Redis manager instance."""
        return self.redis_manager



    def get_state_manager(self):
        """Get the state manager instance."""
        return self.state_manager

    def get_websocket_manager(self):
        """Get the WebSocket manager instance."""
        return self.websocket_manager

    @log_function_call
    def initialize(self, app):
        """
        Initialize all components and plugins.
        """
        # Set the Flask app
        if not hasattr(app, "add_url_rule"):
            raise RuntimeError("AppManager requires a valid Flask app instance.")

        self.flask_app = app
        custom_log(f"AppManager initialized with Flask app: {self.flask_app}")

        # Initialize scheduler
        self.scheduler = BackgroundScheduler()
        self.scheduler.start()

        # Initialize database managers (now using singleton)
        self.db_manager = DatabaseManager(role="read_write")
        # Use the same instance for all database operations
        self.analytics_db = self.db_manager
        self.admin_db = self.db_manager
        self.redis_manager = RedisManager()
        self.rate_limiter_manager = RateLimiterManager()
        self.rate_limiter_manager.set_redis_manager(self.redis_manager)
        self.state_manager = StateManager(redis_manager=self.redis_manager, database_manager=self.db_manager)
        
        # Initialize JWT manager
        from system.managers.jwt_manager import JWTManager
        self.jwt_manager = JWTManager(redis_manager=self.redis_manager)
        
        # Initialize UserActionsManager
        self.user_actions_manager = UserActionsManager()
        
        # Initialize ActionDiscoveryManager
        self.action_discovery_manager = ActionDiscoveryManager(self)
        self.action_discovery_manager.discover_all_actions()
        
        # Initialize WebSocket managers
        self.websocket_manager = WebSocketManager()
        self.websocket_manager.set_jwt_manager(self.jwt_manager)
        self.websocket_manager.set_room_access_check(self.websocket_manager.room_manager.check_room_access)
        self.websocket_manager.initialize(app, use_builtin_handlers=True)
        
        custom_log("✅ Centralized database, Redis, State, JWT, UserActions, ActionDiscovery, and WebSocket managers initialized")

        # Initialize services
        self.services_manager.initialize_services()

        # Register common hooks before module initialization
        self._register_common_hooks()

        # Initialize modules (replaces plugin system)
        custom_log("Initializing modules...")
        self.module_manager.initialize_modules(self)

        # Initialize rate limiting middleware
        self._setup_rate_limiting()
        self._setup_rate_limit_headers()

        # Set up authentication middleware
        self._setup_authentication()

        # Set up monitoring middleware
        self._setup_monitoring()
        
        # Mark as initialized
        self._initialized = True
        
        # Add module status endpoints
        self._setup_module_endpoints()

    def run(self, app, **kwargs):
        """Run the Flask application."""
        app.run(**kwargs)

    def _setup_rate_limiting(self):
        """Set up rate limiting middleware for the Flask app."""
        if not self.flask_app:
            return

        @self.flask_app.before_request
        def check_rate_limit():
            """Middleware to check rate limits before each request."""
            # Skip rate limiting for OPTIONS requests (CORS preflight)
            if request.method == 'OPTIONS':
                return None

            try:
                # Check all enabled rate limits
                limit_types = ['ip']  # Always check IP
                if self.rate_limiter_manager.config['user']['enabled']:
                    limit_types.append('user')
                if self.rate_limiter_manager.config['api_key']['enabled']:
                    limit_types.append('api_key')

                result = self.rate_limiter_manager.check_rate_limit(limit_types)
                
                if not result['allowed']:
                    # Log rate limit hit with details
                    exceeded_types = result['exceeded_types']
                    custom_log(
                        f"Rate limit exceeded for types: {exceeded_types}. "
                        f"IP: {request.remote_addr}, "
                        f"User: {self.rate_limiter_manager._get_user_id()}, "
                        f"API Key: {self.rate_limiter_manager._get_api_key()}",
                        level="WARNING"
                    )
                    
                    # Rate limit exceeded
                    from flask import make_response, jsonify
                    # Calculate retry_after safely
                    retry_after = 60  # Default 60 seconds
                    if result['reset_time']:
                        retry_after = max(result['reset_time'].values()) - int(time.time())
                    
                    response = make_response(
                        jsonify({
                            'error': 'Rate limit exceeded',
                            'message': 'Too many requests',
                            'exceeded_types': exceeded_types,
                            'retry_after': retry_after
                        }),
                        429  # Too Many Requests
                    )
                    
                    # Add rate limit headers if enabled
                    if Config.RATE_LIMIT_HEADERS_ENABLED:
                        for limit_type in limit_types:
                            if limit_type in result['remaining']:
                                prefix = limit_type.upper()
                                response.headers[f'X-RateLimit-{prefix}-Limit'] = str(self.rate_limiter_manager.config[limit_type]['requests'])
                                response.headers[f'X-RateLimit-{prefix}-Remaining'] = str(result['remaining'][limit_type])
                                response.headers[f'X-RateLimit-{prefix}-Reset'] = str(result['reset_time'][limit_type])
                    
                    return response

                # Log rate limit warnings for monitoring
                for limit_type in limit_types:
                    if limit_type in result['remaining'] and result['remaining'][limit_type] < 10:
                        custom_log(
                            f"Rate limit warning for {limit_type}. "
                            f"Remaining: {result['remaining'][limit_type]}",
                            level="WARNING"
                        )

                # Store the result in request context for after_request
                request.rate_limit_result = result

            except RedisError as e:
                # Log Redis errors but allow the request to proceed
                custom_log(f"Redis error in rate limiting: {str(e)}", level="ERROR")
                return None
            except Exception as e:
                # Log other errors but allow the request to proceed
                custom_log(f"Error in rate limiting: {str(e)}", level="ERROR")
                return None

    def _setup_rate_limit_headers(self):
        """Set up rate limit headers middleware for the Flask app."""
        if not self.flask_app:
            return

        @self.flask_app.after_request
        def add_rate_limit_headers(response):
            try:
                if Config.RATE_LIMIT_HEADERS_ENABLED and hasattr(request, 'rate_limit_result'):
                    result = request.rate_limit_result
                    limit_types = ['ip']
                    if self.rate_limiter_manager.config['user']['enabled']:
                        limit_types.append('user')
                    if self.rate_limiter_manager.config['api_key']['enabled']:
                        limit_types.append('api_key')
                    
                    for limit_type in limit_types:
                        if limit_type in result['remaining']:
                            prefix = limit_type.upper()
                            response.headers[f'X-RateLimit-{prefix}-Limit'] = str(self.rate_limiter_manager.config[limit_type]['requests'])
                            response.headers[f'X-RateLimit-{prefix}-Remaining'] = str(result['remaining'][limit_type])
                            response.headers[f'X-RateLimit-{prefix}-Reset'] = str(result['reset_time'][limit_type])
            except Exception as e:
                custom_log(f"Error adding rate limit headers: {str(e)}", level="ERROR")
            return response
    
    def _setup_module_endpoints(self):
        """Set up module management and status endpoints."""
        if not self.flask_app:
            return

        @self.flask_app.route('/modules/status')
        def modules_status():
            """Get status of all modules."""
            try:
                status = self.module_manager.get_module_status()
                return status, 200
            except Exception as e:
                custom_log(f"Error getting module status: {e}", level="ERROR")
                return {'error': 'Failed to get module status'}, 500

        @self.flask_app.route('/modules/<module_key>/health')
        def module_health(module_key):
            """Get health check for specific module."""
            try:
                module = self.module_manager.get_module(module_key)
                if not module:
                    return {'error': 'Module not found'}, 404
                
                health = module.health_check()
                return health, 200
            except Exception as e:
                custom_log(f"Error getting module health: {e}", level="ERROR")
                return {'error': 'Failed to get module health'}, 500

        custom_log("Module management endpoints registered")

    def _setup_authentication(self):
        """Set up global authentication middleware for the Flask app."""
        if not self.flask_app:
            return

        # Initialize API Key Manager
        from system.managers.api_key_manager import APIKeyManager
        self.api_key_manager = APIKeyManager(self.redis_manager)

        # Register security headers at application level
        @self.flask_app.after_request
        def add_security_headers(response):
            """Add security headers to all responses."""
            response.headers['X-Content-Type-Options'] = 'nosniff'
            response.headers['X-Frame-Options'] = 'DENY'
            response.headers['X-XSS-Protection'] = '1; mode=block'
            response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
            response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
            response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
            return response

        @self.flask_app.before_request
        def authenticate_request():
            """Clean authentication middleware based on route prefixes."""
            # Skip authentication for OPTIONS requests (CORS preflight)
            if request.method == 'OPTIONS':
                return None
            
            # Determine authentication requirements based on route prefix
            auth_required = None
            
            # Check route-based authentication rules
            if request.path.startswith('/userauth/'):
                auth_required = 'jwt'
            elif request.path.startswith('/keyauth/'):
                auth_required = 'key'
            elif request.path.startswith('/public/'):
                auth_required = None  # Explicitly public
            else:
                # Default to public for all other routes
                auth_required = None
            
            # If no authentication required, continue
            if auth_required is None:
                return None
            
            # Handle JWT authentication
            if auth_required == 'jwt':
                auth_header = request.headers.get('Authorization')
                if not auth_header or not auth_header.startswith('Bearer '):
                    return jsonify({
                        'error': 'Missing or invalid authorization header',
                        'message': 'JWT token required for this endpoint.',
                        'code': 'JWT_REQUIRED'
                    }), 401
                
                # Extract and validate JWT token
                token = auth_header.split(' ')[1]
                try:
                    from system.managers.jwt_manager import TokenType
                    payload = self.jwt_manager.verify_token(token, TokenType.ACCESS)
                    if not payload:
                        return jsonify({
                            'error': 'Invalid or expired token',
                            'message': 'Please login again to get a fresh token.',
                            'code': 'TOKEN_INVALID'
                        }), 401
                    
                    # Set user context for the request
                    request.user_id = payload.get('user_id')
                    request.user_payload = payload
                    
                    custom_log(f"✅ JWT authenticated request for user: {request.user_id}")
                    return None
                    
                except Exception as e:
                    custom_log(f"❌ JWT authentication error: {str(e)}", level="ERROR")
                    return jsonify({
                        'error': 'Token validation failed',
                        'message': 'Please login again.',
                        'code': 'TOKEN_VALIDATION_ERROR'
                    }), 401
            
            # Handle API key authentication
            if auth_required == 'key':
                api_key = request.headers.get('X-API-Key')
                if not api_key:
                    return jsonify({
                        'error': 'Missing API key',
                        'message': 'API key required for this endpoint.',
                        'code': 'API_KEY_REQUIRED'
                    }), 401
                
                # Validate API key
                api_key_data = self.api_key_manager.validate_api_key(api_key)
                if not api_key_data:
                    return jsonify({
                        'error': 'Invalid or expired API key',
                        'message': 'Please provide a valid API key.',
                        'code': 'API_KEY_INVALID'
                    }), 401
                
                # Set app context for the request
                request.app_id = api_key_data.get('app_id')
                request.app_name = api_key_data.get('app_name')
                request.app_permissions = api_key_data.get('permissions', [])
                request.api_key_data = api_key_data
                
                custom_log(f"✅ API key authenticated for app: {request.app_name} ({request.app_id})")
                return None

        custom_log("✅ Clean authentication middleware configured with security headers")

    @log_function_call
    def register_hook(self, hook_name):
        """
        Register a new hook by delegating to the HooksManager.
        :param hook_name: str - The name of the hook.
        """
        self.hooks_manager.register_hook(hook_name)
        custom_log(f"Hook '{hook_name}' registered via AppManager.")

    @log_function_call
    def register_hook_callback(self, hook_name, callback, priority=10, context=None):
        """
        Register a callback for a specific hook by delegating to the HooksManager.
        :param hook_name: str - The name of the hook.
        :param callback: callable - The callback function.
        :param priority: int - Priority of the callback (lower number = higher priority).
        :param context: str - Optional context for the callback.
        """
        self.hooks_manager.register_hook_callback(hook_name, callback, priority, context)
        callback_name = callback.__name__ if hasattr(callback, "__name__") else str(callback)
        custom_log(f"Callback '{callback_name}' registered for hook '{hook_name}' (priority: {priority}, context: {context}).")

    @log_function_call
    def trigger_hook(self, hook_name, data=None, context=None):
        """
        Trigger a specific hook by delegating to the HooksManager.
        :param hook_name: str - The name of the hook to trigger.
        :param data: Any - Data to pass to the callback.
        :param context: str - Optional context to filter callbacks.
        """
        custom_log(f"Triggering hook '{hook_name}' with data: {data} and context: {context}.")
        self.hooks_manager.trigger_hook(hook_name, data, context)

    def _setup_monitoring(self):
        """Set up monitoring middleware for the Flask app."""
        if not self.flask_app:
            return
            
        @self.flask_app.before_request
        def before_request():
            request.start_time = time.time()
            request.request_size = len(request.get_data())
            
        @self.flask_app.after_request
        def after_request(response):
            try:
                # Calculate request duration safely
                if hasattr(request, 'start_time'):
                    duration = time.time() - request.start_time
                else:
                    duration = 0
                
                # Track request metrics
                metrics_collector.track_request(
                    method=request.method,
                    endpoint=request.endpoint,
                    status=response.status_code,
                    duration=duration,
                    size=getattr(request, 'request_size', 0)
                )
            except Exception as e:
                custom_log(f"Error in after_request monitoring: {e}", level="ERROR")
            
            return response
            
        # Set up periodic system metrics collection
        self._setup_system_metrics()
        
    def _register_common_hooks(self):
        """Register common hooks that modules can use."""
        try:
            # Register user_created hook
            self.register_hook("user_created")
            custom_log("✅ Registered common hook: user_created")
            
            # Add more common hooks here as needed
            # self.register_hook("payment_processed")
            # self.register_hook("user_login")
            # self.register_hook("user_logout")
            
        except Exception as e:
            custom_log(f"❌ Error registering common hooks: {e}", level="ERROR")

    def _setup_system_metrics(self):
        """Set up periodic collection of system metrics."""
        def update_system_metrics():
            try:
                # Update MongoDB connections
                if hasattr(self, 'db_manager'):
                    metrics_collector.update_mongodb_connections(
                        self.db_manager.get_connection_count()
                    )
                
                # Update Redis connections
                if hasattr(self, 'redis_manager'):
                    metrics_collector.update_redis_connections(
                        self.redis_manager.get_connection_count()
                    )
            except Exception as e:
                custom_log(f"Error updating system metrics: {e}", level="ERROR")
        
        # Schedule periodic updates
        self.scheduler.add_job(
            update_system_metrics,
            'interval',
            seconds=15,
            id='system_metrics_update'
        )
