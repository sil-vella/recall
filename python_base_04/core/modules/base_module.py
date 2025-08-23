from abc import ABC, abstractmethod
from typing import List, Dict, Any, Optional
from tools.logger.custom_logging import custom_log
import logging


class BaseModule(ABC):
    """
    Abstract base class for all application modules.
    Provides a standardized interface and common functionality.
    """
    
    def __init__(self, app_manager=None):
        """
        Initialize the base module.
        
        :param app_manager: Reference to the main AppManager instance
        """
        self.app_manager = app_manager
        self.app = None  # Flask app reference
        self.registered_routes = []
        self.dependencies = []
        self.module_name = self.__class__.__name__
        self.logger = logging.getLogger(f"modules.{self.module_name}")
        self._initialized = False
        
        custom_log(f"Module {self.module_name} created")
    
    @abstractmethod
    def initialize(self, app_manager):
        """
        Initialize the module with the AppManager.
        This method must be implemented by all modules.
        
        :param app_manager: AppManager instance
        """
        self.app_manager = app_manager
        pass
    
    def register_routes(self):
        """
        Register module-specific routes with the Flask application.
        Override this method to add custom routes.
        """
        custom_log(f"No routes to register for module {self.module_name}")
    
    def configure(self):
        """
        Configure module-specific settings.
        Override this method for custom configuration.
        """
        custom_log(f"No configuration needed for module {self.module_name}")
    
    def dispose(self):
        """
        Cleanup module resources.
        Override this method for custom cleanup logic.
        """
        custom_log(f"Disposing module {self.module_name}")
        self._initialized = False
    
    def declare_dependencies(self) -> List[str]:
        """
        Return list of module names this module depends on.
        
        :return: List of module dependency names
        """
        return self.dependencies
    
    def is_initialized(self) -> bool:
        """
        Check if the module has been properly initialized.
        
        :return: True if initialized, False otherwise
        """
        return self._initialized
    
    def get_module_info(self) -> Dict[str, Any]:
        """
        Get information about this module.
        
        :return: Dictionary containing module metadata
        """
        return {
            'name': self.module_name,
            'initialized': self._initialized,
            'dependencies': self.dependencies,
            'routes_count': len(self.registered_routes),
            'routes': [route[0] if isinstance(route, tuple) else str(route) for route in self.registered_routes]
        }
    
    def health_check(self) -> Dict[str, Any]:
        """
        Perform a health check on the module.
        Override this method for custom health checks.
        
        :return: Dictionary containing health status
        """
        return {
            'module': self.module_name,
            'status': 'healthy' if self._initialized else 'not_initialized',
            'details': 'Module is functioning normally' if self._initialized else 'Module not initialized'
        }
    
    def _register_route_helper(self, route: str, view_func, methods: List[str] = None, auth: str = None):
        """
        Helper method to register a route and track it.
        
        :param route: URL route pattern
        :param view_func: View function to handle the route
        :param methods: HTTP methods allowed for this route
        :param auth: Authentication type - 'jwt', 'key', or None for public
        """
        if not self.app:
            raise RuntimeError(f"Cannot register route {route} - Flask app not initialized")
        
        if methods is None:
            methods = ["GET"]
        
        # Register with Flask
        self.app.add_url_rule(route, view_func=view_func, methods=methods)
        
        # Track route with authentication info
        route_info = (route, view_func.__name__, methods, auth)
        self.registered_routes.append(route_info)
        
        auth_info = f" (auth: {auth})" if auth else " (public)"
        self.logger.info(f"Registered route: {route} with methods {methods}{auth_info}")
        custom_log(f"Module {self.module_name} registered route: {route}{auth_info}")
    
    def _register_auth_route_helper(self, route: str, view_func, methods: List[str] = None):
        """
        Smart route registration that automatically determines authentication based on route prefix.
        
        Authentication rules:
        - /userauth/* -> Requires JWT token
        - /keyauth/* -> Requires API key
        - /public/* -> No authentication required
        - All other routes -> No authentication required (public)
        
        :param route: URL route pattern
        :param view_func: View function to handle the route
        :param methods: HTTP methods allowed for this route
        """
        auth_type = None
        
        # Determine authentication type based on route prefix
        if route.startswith('/userauth/'):
            auth_type = 'jwt'
        elif route.startswith('/keyauth/'):
            auth_type = 'key'
        elif route.startswith('/public/'):
            auth_type = None  # Explicitly public
        else:
            auth_type = None  # Default to public
        
        # Register with determined auth type
        self._register_route_helper(route, view_func, methods, auth_type) 