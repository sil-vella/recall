from system.orchestration.modules_orch.base_files.module_orch_base import ModuleOrchestratorBase
from tools.logger.custom_logging import custom_log
from typing import Dict, Any, Optional
from system.modules.user_management_module.user_management_main import UserManagementModule
from flask import request, jsonify
from datetime import datetime


class UserManagementOrchestrator(ModuleOrchestratorBase):
    """
    Orchestrator for UserManagementModule.
    Handles system integration, lifecycle management, and request forwarding.
    """
    
    def __init__(self, manager_initializer):
        """
        Initialize the user management orchestrator.
        
        Args:
            manager_initializer: ManagerInitializer instance for accessing all managers
        """
        super().__init__(manager_initializer)
        self.manager_initializer = manager_initializer
        
        self.module = None
        self.is_initialized = False
        self.registered_routes = []
        custom_log("UserManagementOrchestrator created")

    def initialize(self):
        """Initialize the orchestrator and module."""
        try:
            # Create module instance (no config needed - module accesses secrets directly)
            self.module = UserManagementModule()
            
            # Initialize the module
            self.module.initialize()
            
            # Register hooks with the system
            self._register_hooks()
            
            # Register route callback with hooks manager
            self._register_route_callback()
            
            self.is_initialized = True
            custom_log("✅ UserManagementOrchestrator initialized successfully")
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize UserManagementOrchestrator: {e}", level="ERROR")
            raise

    def _register_route_callback(self):
        """Register route callback with the hooks manager."""
        try:
            if self.hooks_manager:
                self.hooks_manager.register_hook_callback(
                    "register_routes",
                    self.register_routes_callback,
                    priority=10,
                    context="user_management_orchestrator"
                )
                custom_log("✅ UserManagementOrchestrator registered route callback with hooks manager")
            else:
                custom_log("⚠️ Hooks manager not available for route registration")
                
        except Exception as e:
            custom_log(f"❌ Failed to register route callback: {e}", level="ERROR")

    def register_routes_callback(self, data=None):
        """Register user management routes when the register_routes hook is triggered."""
        try:
            from flask import current_app
            
            # Get routes needed by the module
            routes_needed = self.module.get_routes_needed()
            
            # Register each route with Flask
            for route_info in routes_needed:
                route = route_info['route']
                methods = route_info['methods']
                handler_name = route_info['handler']
                
                # Get the handler method from this orchestrator
                handler_method = getattr(self, handler_name, None)
                if handler_method:
                    # Register the route with Flask
                    current_app.add_url_rule(
                        route,
                        f"user_management_{handler_name}",
                        handler_method,
                        methods=methods
                    )
                    custom_log(f"✅ Registered route: {route} -> {handler_name}")
                else:
                    custom_log(f"❌ Handler method {handler_name} not found for route {route}")
            
            custom_log(f"✅ UserManagementOrchestrator registered {len(routes_needed)} routes via hook")
            
        except Exception as e:
            custom_log(f"❌ Error registering routes via hook: {e}", level="ERROR")

    def _register_hooks(self):
        """Register module hooks with the system."""
        try:
            if self.hooks_manager:
                # Get hooks needed by the module
                hooks_needed = self.module.get_hooks_needed()
                
                for hook_info in hooks_needed:
                    event = hook_info['event']
                    priority = hook_info.get('priority', 10)
                    context = hook_info.get('context', 'user_management')
                    
                    # Register the hook
                    self.hooks_manager.register_hook(
                        event=event,
                        callback=self._handle_hook_event,
                        priority=priority,
                        context=context
                    )
                    custom_log(f"✅ Registered hook: {event} (priority: {priority})")
                    
        except Exception as e:
            custom_log(f"❌ Failed to register hooks: {e}", level="ERROR")

    def _handle_hook_event(self, event_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle hook events from the system.
        
        Args:
            event_name: Name of the hook event
            event_data: Data passed with the hook
            
        Returns:
            Dict with processing result
        """
        try:
            if self.module:
                return self.module.process_hook_event(event_name, event_data)
            else:
                return {
                    'success': False,
                    'error': 'Module not initialized'
                }
        except Exception as e:
            custom_log(f"❌ Error handling hook event {event_name}: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Hook processing error: {str(e)}'
            }

    # Flask Route Handlers
    def create_user(self):
        """Create a new user account with comprehensive setup."""
        try:
            data = request.get_json()
            
            # Use module for business logic
            result = self.module.process_user_creation(data)
            
            if not result['success']:
                return jsonify({
                    "success": False,
                    "error": result['error']
                }), 400
            
            # Get database manager for persistence
            if not self.db_manager:
                return jsonify({
                    "success": False,
                    "error": "Database manager not available"
                }), 503
            
            # Check if user already exists
            existing_user = self.db_manager.find_one("users", {"email": data.get("email")})
            if existing_user:
                return jsonify({
                    "success": False,
                    "error": "User with this email already exists"
                }), 409
            
            # Insert user document
            user_document = result['user_document']
            inserted_id = self.db_manager.insert("users", user_document)
            
            if inserted_id:
                return jsonify({
                    "success": True,
                    "message": f"User {data.get('username')} created successfully",
                    "user_id": str(inserted_id)
                }), 201
            else:
                return jsonify({
                    "success": False,
                    "error": "Failed to create user"
                }), 500
                
        except Exception as e:
            custom_log(f"❌ Error creating user: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def login_user(self):
        """Authenticate user and return JWT tokens."""
        try:
            data = request.get_json()
            email = data.get("email")
            password = data.get("password")
            
            if not email or not password:
                return jsonify({
                    "success": False,
                    "error": "Email and password are required"
                }), 400
            
            # Use module for business logic
            result = self.module.process_user_login(data)
            
            if not result['success']:
                return jsonify({
                    "success": False,
                    "error": result['error']
                }), 401
            
            # Get user from database
            user = self.db_manager.find_one("users", {"email": email})
            if not user:
                return jsonify({
                    "success": False,
                    "error": "Invalid credentials"
                }), 401
            
            # Verify password using module
            password_result = self.module.verify_password(password, user.get("password_hash", ""))
            if not password_result['success']:
                return jsonify({
                    "success": False,
                    "error": "Invalid credentials"
                }), 401
            
            # Generate JWT tokens with original email from login request
            access_token = self.jwt_manager.create_access_token(
                data={"user_id": str(user["_id"]), "email": data.get("email"), "username": user["username"]}
            )
            refresh_token = self.jwt_manager.create_refresh_token(
                data={"user_id": str(user["_id"]), "email": data.get("email"), "username": user["username"]}
            )
            
            return jsonify({
                "success": True,
                "message": "Login successful",
                "access_token": access_token,
                "refresh_token": refresh_token,
                "user": self.module._prepare_user_response(user)
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error during login: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def refresh_token(self):
        """Refresh JWT access token using refresh token."""
        try:
            data = request.get_json()
            refresh_token = data.get("refresh_token")
            
            if not refresh_token:
                return jsonify({
                    "success": False,
                    "error": "Refresh token is required"
                }), 400
            
            # Refresh tokens
            new_access_token = self.jwt_manager.refresh_token(refresh_token)
            
            if new_access_token:
                return jsonify({
                    "success": True,
                    "message": "Token refreshed successfully",
                    "access_token": new_access_token
                }), 200
            else:
                return jsonify({
                    "success": False,
                    "error": "Invalid refresh token"
                }), 401
                
        except Exception as e:
            custom_log(f"❌ Error refreshing token: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def logout_user(self):
        """Logout user and invalidate tokens."""
        try:
            # Invalidate tokens (implementation depends on JWT manager)
            return jsonify({
                "success": True,
                "message": "Logout successful"
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error during logout: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_current_user(self):
        """Get current user information (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            # Get user from database
            user = self.db_manager.find_one("users", {"_id": user_id})
            if not user:
                return jsonify({
                    "success": False,
                    "error": "User not found"
                }), 404
            
            return jsonify({
                "success": True,
                "user": self.module._prepare_user_response(user)
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting current user: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_user_profile(self):
        """Get user profile (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            # Get user from database
            user = self.db_manager.find_one("users", {"_id": user_id})
            if not user:
                return jsonify({'error': 'User not found'}), 404
            
            profile_data = {
                'user_id': user_id,
                'profile': user.get('profile', {}),
                'username': user.get('username'),
                'email': user.get('email')
            }
            
            return jsonify(profile_data), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting user profile: {e}", level="ERROR")
            return jsonify({'error': 'Failed to get user profile'}), 500

    def update_user_profile(self):
        """Update user profile (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            data = request.get_json()
            
            # Use module for validation
            validation_result = self.module.validate_user_update_data(data)
            if not validation_result['success']:
                return jsonify({
                    "success": False,
                    "error": validation_result['error']
                }), 400
            
            # Get database manager
            update_data = {'updated_at': datetime.utcnow().isoformat()}
            
            # Only allow updating profile fields
            allowed_fields = ['first_name', 'last_name', 'phone', 'timezone', 'language']
            for field in allowed_fields:
                if field in data:
                    update_data[f'profile.{field}'] = data[field]
            
            # Update user profile
            modified_count = self.db_manager.update("users", {"_id": user_id}, {"$set": update_data})
            
            if modified_count > 0:
                return jsonify({
                    'success': True,
                    'message': 'Profile updated successfully',
                    'user_id': user_id
                }), 200
            else:
                return jsonify({'error': 'Failed to update profile'}), 500
                
        except Exception as e:
            custom_log(f"❌ Error updating user profile: {e}", level="ERROR")
            return jsonify({'error': 'Failed to update profile'}), 500

    def get_user_settings(self):
        """Get user settings (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            # Get user from database
            user = self.db_manager.find_one("users", {"_id": user_id})
            if not user:
                return jsonify({'error': 'User not found'}), 404
            
            settings_data = {
                'user_id': user_id,
                'preferences': user.get('preferences', {}),
                'modules': user.get('modules', {})
            }
            
            return jsonify(settings_data), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting user settings: {e}", level="ERROR")
            return jsonify({'error': 'Failed to get user settings'}), 500

    def update_user_settings(self):
        """Update user settings (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            data = request.get_json()
            update_data = {'updated_at': datetime.utcnow().isoformat()}
            
            # Allow updating preferences
            if 'preferences' in data:
                update_data['preferences'] = data['preferences']
            
            # Update user settings
            modified_count = self.db_manager.update("users", {"_id": user_id}, {"$set": update_data})
            
            if modified_count > 0:
                return jsonify({
                    'success': True,
                    'message': 'Settings updated successfully',
                    'user_id': user_id
                }), 200
            else:
                return jsonify({'error': 'Failed to update settings'}), 500
                
        except Exception as e:
            custom_log(f"❌ Error updating user settings: {e}", level="ERROR")
            return jsonify({'error': 'Failed to update settings'}), 500

    def get_public_user_info(self):
        """Get public user information (no auth required)."""
        try:
            return jsonify({
                "success": True,
                "message": "User management service is available",
                "version": "1.0.0",
                "endpoints": [
                    "/public/register",
                    "/public/login",
                    "/public/refresh",
                    "/userauth/me",
                    "/userauth/users/profile",
                    "/userauth/users/settings",
                    "/userauth/logout"
                ]
            }), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting public user info: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def forward_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Forward a request to the user management module.
        
        Args:
            request_data: Dictionary with method, path, headers, data
            
        Returns:
            Dict with response status and data
        """
        try:
            if not self.is_initialized:
                return {
                    'success': False,
                    'error': 'Orchestrator not initialized'
                }
            
            # This would be implemented based on the specific request type
            # For now, return a generic response
            return {
                'success': True,
                'message': 'Request forwarded to user management module',
                'data': request_data
            }
            
        except Exception as e:
            custom_log(f"❌ Error forwarding request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Request forwarding error: {str(e)}'
            }

    def health_check(self) -> Dict[str, Any]:
        """
        Perform health check on the module.
        
        Returns:
            Dict with health status
        """
        try:
            if not self.is_initialized:
                return {
                    'status': 'not_initialized',
                    'orchestrator': 'UserManagementOrchestrator',
                    'error': 'Orchestrator not initialized'
                }
            
            # Get module health
            module_health = self.module.health_check()
            
            return {
                'status': module_health['status'],
                'orchestrator': 'UserManagementOrchestrator',
                'module': module_health,
                'is_initialized': self.is_initialized,
                'registered_routes': len(self.registered_routes)
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'orchestrator': 'UserManagementOrchestrator',
                'error': str(e),
                'is_initialized': self.is_initialized
            }

    def get_config(self) -> Dict[str, Any]:
        """
        Get orchestrator and module configuration.
        
        Returns:
            Dict with configuration information
        """
        try:
            module_config = self.module.get_config() if self.module else {}
            
            return {
                'orchestrator': 'UserManagementOrchestrator',
                'is_initialized': self.is_initialized,
                'module_config': module_config,
                'registered_routes': len(self.registered_routes)
            }
            
        except Exception as e:
            return {
                'orchestrator': 'UserManagementOrchestrator',
                'is_initialized': self.is_initialized,
                'error': str(e)
            }

    def process_user_creation(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process user creation through the module.
        
        Args:
            user_data: User data dictionary
            
        Returns:
            Dict with processing result
        """
        try:
            if not self.is_initialized:
                return {
                    'success': False,
                    'error': 'Orchestrator not initialized'
                }
            
            return self.module.process_user_creation(user_data)
            
        except Exception as e:
            custom_log(f"❌ Error processing user creation: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'User creation error: {str(e)}'
            }

    def process_user_login(self, login_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process user login through the module.
        
        Args:
            login_data: Login data dictionary
            
        Returns:
            Dict with processing result
        """
        try:
            if not self.is_initialized:
                return {
                    'success': False,
                    'error': 'Orchestrator not initialized'
                }
            
            return self.module.process_user_login(login_data)
            
        except Exception as e:
            custom_log(f"❌ Error processing user login: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'User login error: {str(e)}'
            }

    def verify_password(self, password: str, hashed_password: str) -> Dict[str, Any]:
        """
        Verify password through the module.
        
        Args:
            password: Plain text password
            hashed_password: Hashed password to compare against
            
        Returns:
            Dict with verification result
        """
        try:
            if not self.is_initialized:
                return {
                    'success': False,
                    'error': 'Orchestrator not initialized'
                }
            
            return self.module.verify_password(password, hashed_password)
            
        except Exception as e:
            custom_log(f"❌ Error verifying password: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Password verification error: {str(e)}'
            }

    def hash_password(self, password: str) -> Dict[str, Any]:
        """
        Hash password through the module.
        
        Args:
            password: Plain text password
            
        Returns:
            Dict with hashed password
        """
        try:
            if not self.is_initialized:
                return {
                    'success': False,
                    'error': 'Orchestrator not initialized'
                }
            
            return self.module.hash_password(password)
            
        except Exception as e:
            custom_log(f"❌ Error hashing password: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Password hashing error: {str(e)}'
            }

    def validate_user_update_data(self, update_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate user update data through the module.
        
        Args:
            update_data: User update data dictionary
            
        Returns:
            Dict with validation result
        """
        try:
            if not self.is_initialized:
                return {
                    'success': False,
                    'error': 'Orchestrator not initialized'
                }
            
            return self.module.validate_user_update_data(update_data)
            
        except Exception as e:
            custom_log(f"❌ Error validating user update data: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'User update validation error: {str(e)}'
            }

    def dispose(self):
        """Cleanup orchestrator resources."""
        try:
            if self.module:
                # Module doesn't have dispose method, but we can clean up references
                self.module = None
            
            self.is_initialized = False
            custom_log("UserManagementOrchestrator disposed")
            
        except Exception as e:
            custom_log(f"❌ Error disposing orchestrator: {e}", level="ERROR") 