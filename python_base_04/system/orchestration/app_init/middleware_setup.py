"""
Middleware Setup

This module handles the setup and configuration of all Flask middleware.
It centralizes rate limiting, authentication, monitoring, and other middleware setup.
"""

from flask import request, jsonify, make_response
from tools.logger.custom_logging import custom_log
from utils.config.config import Config
from system.monitoring.metrics_collector import metrics_collector
import time
from redis.exceptions import RedisError


class MiddlewareSetup:
    """
    Handles the setup and configuration of all Flask middleware.
    
    This class is responsible for setting up rate limiting, authentication,
    monitoring, and other middleware components for the Flask application.
    """
    
    def __init__(self, app_initializer):
        """
        Initialize the MiddlewareSetup.
        
        Args:
            app_initializer: Reference to the main AppInitializer instance
        """
        self.app_initializer = app_initializer
        self.flask_app = None
        
        custom_log("MiddlewareSetup created")

    def setup_all_middleware(self):
        """Set up all middleware components for the Flask application."""
        if not self.app_initializer.flask_app:
            custom_log("⚠️ No Flask app available for middleware setup")
            return
            
        self.flask_app = self.app_initializer.flask_app
        custom_log("Setting up all middleware components...")
        
        # Set up rate limiting middleware
        self._setup_rate_limiting()
        self._setup_rate_limit_headers()
        
        # Set up authentication middleware
        self._setup_authentication()
        
        # Set up monitoring middleware
        self._setup_monitoring()
        
        # Set up module endpoints
        self._setup_module_endpoints()
        
        # Set up system metrics
        self._setup_system_metrics()
        
        custom_log("✅ All middleware components set up successfully")

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
                if self.app_initializer.rate_limiter_manager.config['user']['enabled']:
                    limit_types.append('user')
                if self.app_initializer.rate_limiter_manager.config['api_key']['enabled']:
                    limit_types.append('api_key')

                result = self.app_initializer.rate_limiter_manager.check_rate_limit(limit_types)
                
                if not result['allowed']:
                    # Log rate limit hit with details
                    exceeded_types = result['exceeded_types']
                    custom_log(
                        f"Rate limit exceeded for types: {exceeded_types}. "
                        f"IP: {request.remote_addr}, "
                        f"User: {self.app_initializer.rate_limiter_manager._get_user_id()}, "
                        f"API Key: {self.app_initializer.rate_limiter_manager._get_api_key()}",
                        level="WARNING"
                    )
                    
                    # Rate limit exceeded
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
                                response.headers[f'X-RateLimit-{prefix}-Limit'] = str(self.app_initializer.rate_limiter_manager.config[limit_type]['requests'])
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
                    if self.app_initializer.rate_limiter_manager.config['user']['enabled']:
                        limit_types.append('user')
                    if self.app_initializer.rate_limiter_manager.config['api_key']['enabled']:
                        limit_types.append('api_key')
                    
                    for limit_type in limit_types:
                        if limit_type in result['remaining']:
                            prefix = limit_type.upper()
                            response.headers[f'X-RateLimit-{prefix}-Limit'] = str(self.app_initializer.rate_limiter_manager.config[limit_type]['requests'])
                            response.headers[f'X-RateLimit-{prefix}-Remaining'] = str(result['remaining'][limit_type])
                            response.headers[f'X-RateLimit-{prefix}-Reset'] = str(result['reset_time'][limit_type])
            except Exception as e:
                custom_log(f"Error adding rate limit headers: {str(e)}", level="ERROR")
            return response

    def _setup_authentication(self):
        """Set up global authentication middleware for the Flask app."""
        if not self.flask_app:
            return

        # Initialize API Key Manager
        from system.managers.api_key_manager import APIKeyManager
        self.app_initializer.api_key_manager = APIKeyManager(self.app_initializer.redis_manager)

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
                    payload = self.app_initializer.jwt_manager.verify_token(token, TokenType.ACCESS)
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
                api_key_data = self.app_initializer.api_key_manager.validate_api_key(api_key)
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

    def _setup_module_endpoints(self):
        """Set up module management and status endpoints."""
        if not self.flask_app:
            return

        @self.flask_app.route('/modules/status')
        def modules_status():
            """Get status of all modules."""
            try:
                # Module status now handled by individual managers
                status = {"modules": {}, "total_modules": 0, "initialized_modules": 0}
                return status, 200
            except Exception as e:
                custom_log(f"Error getting module status: {e}", level="ERROR")
                return {'error': 'Failed to get module status'}, 500

        @self.flask_app.route('/modules/<module_key>/health')
        def module_health(module_key):
            """Get health check for specific module."""
            try:
                # Module health now handled by individual managers
                return {'error': 'Module health checks now handled by individual managers'}, 501
            except Exception as e:
                custom_log(f"Error getting module health: {e}", level="ERROR")
                return {'error': 'Failed to get module health'}, 500

        custom_log("Module management endpoints registered")

    def _setup_system_metrics(self):
        """Set up periodic collection of system metrics."""
        def update_system_metrics():
            try:
                # Update MongoDB connections
                if hasattr(self.app_initializer, 'db_manager'):
                    metrics_collector.update_mongodb_connections(
                        self.app_initializer.db_manager.get_connection_count()
                    )
                
                # Update Redis connections
                if hasattr(self.app_initializer, 'redis_manager'):
                    metrics_collector.update_redis_connections(
                        self.app_initializer.redis_manager.get_connection_count()
                    )
            except Exception as e:
                custom_log(f"Error updating system metrics: {e}", level="ERROR")
        
        # Schedule periodic updates
        if self.app_initializer.scheduler:
            self.app_initializer.scheduler.add_job(
                update_system_metrics,
                'interval',
                seconds=15,
                id='system_metrics_update'
            ) 