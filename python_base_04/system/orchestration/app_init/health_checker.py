"""
Health Checker

This module handles all health checking functionality for the application.
It provides methods to check the health of database, Redis, and other components.
"""

from tools.logger.custom_logging import custom_log


class HealthChecker:
    """
    Handles health checking for all application components.
    
    This class provides methods to check the health of database connections,
    Redis connections, and other critical system components.
    """
    
    def __init__(self, app_initializer):
        """
        Initialize the HealthChecker.
        
        Args:
            app_initializer: Reference to the main AppInitializer instance
        """
        self.app_initializer = app_initializer
        custom_log("HealthChecker created")

    def check_database_connection(self) -> bool:
        """
        Check if the database connection is healthy.
        
        Returns:
            bool: True if database connection is healthy, False otherwise
        """
        try:
            if not self.app_initializer.db_manager:
                custom_log("Database manager not available", level="WARNING")
                return False
                
            # Try to execute a simple query to check connection
            is_healthy = self.app_initializer.db_manager.check_connection()
            
            if is_healthy:
                custom_log("✅ Database connection is healthy")
            else:
                custom_log("❌ Database connection check failed", level="ERROR")
                
            return is_healthy
            
        except Exception as e:
            custom_log(f"❌ Database health check failed: {e}", level="ERROR")
            return False

    def check_redis_connection(self) -> bool:
        """
        Check if the Redis connection is healthy.
        
        Returns:
            bool: True if Redis connection is healthy, False otherwise
        """
        try:
            if not self.app_initializer.redis_manager:
                custom_log("Redis manager not available", level="WARNING")
                return False
                
            # Try to execute a PING command
            is_healthy = self.app_initializer.redis_manager.ping()
            
            if is_healthy:
                custom_log("✅ Redis connection is healthy")
            else:
                custom_log("❌ Redis connection check failed", level="ERROR")
                
            return is_healthy
            
        except Exception as e:
            custom_log(f"❌ Redis health check failed: {e}", level="ERROR")
            return False

    def check_state_manager_health(self) -> dict:
        """
        Check the health of the state manager.
        
        Returns:
            dict: Health status information
        """
        try:
            if not self.app_initializer.state_manager:
                return {
                    'status': 'unhealthy',
                    'reason': 'State manager not available',
                    'details': 'State manager has not been initialized'
                }
            
            health_info = self.app_initializer.state_manager.health_check()
            return health_info
            
        except Exception as e:
            custom_log(f"❌ State manager health check failed: {e}", level="ERROR")
            return {
                'status': 'unhealthy',
                'reason': f'State manager health check error: {str(e)}',
                'details': 'Exception occurred during health check'
            }

    def check_module_health(self, module_key: str) -> dict:
        """
        Check the health of a specific module.
        
        Args:
            module_key: The key of the module to check
            
        Returns:
            dict: Health status information for the module
        """
        try:
            module = self.app_initializer.module_manager.get_module(module_key)
            if not module:
                return {
                    'status': 'not_found',
                    'reason': f'Module {module_key} not found',
                    'details': 'Module is not registered or has been removed'
                }
            
            health_info = module.health_check()
            return health_info
            
        except Exception as e:
            custom_log(f"❌ Module health check failed for {module_key}: {e}", level="ERROR")
            return {
                'status': 'unhealthy',
                'reason': f'Module health check error: {str(e)}',
                'details': 'Exception occurred during module health check'
            }

    def check_all_modules_health(self) -> dict:
        """
        Check the health of all registered modules.
        
        Returns:
            dict: Health status information for all modules
        """
        try:
            module_status = self.app_initializer.module_manager.get_module_status()
            unhealthy_modules = []
            
            for module_key, module_info in module_status.get('modules', {}).items():
                if module_info.get('health', {}).get('status') != 'healthy':
                    unhealthy_modules.append({
                        'module': module_key,
                        'status': module_info.get('health', {}).get('status', 'unknown'),
                        'details': module_info.get('health', {}).get('details', 'No details available')
                    })
            
            return {
                'status': 'healthy' if not unhealthy_modules else 'degraded',
                'total_modules': module_status.get('total_modules', 0),
                'healthy_modules': module_status.get('total_modules', 0) - len(unhealthy_modules),
                'unhealthy_modules': unhealthy_modules,
                'details': f"{len(unhealthy_modules)} unhealthy modules found"
            }
            
        except Exception as e:
            custom_log(f"❌ All modules health check failed: {e}", level="ERROR")
            return {
                'status': 'unhealthy',
                'reason': f'Modules health check error: {str(e)}',
                'details': 'Exception occurred during modules health check'
            }

    def comprehensive_health_check(self) -> dict:
        """
        Perform a comprehensive health check of all system components.
        
        Returns:
            dict: Comprehensive health status information
        """
        health_report = {
            'overall_status': 'healthy',
            'checks': {},
            'timestamp': None
        }
        
        try:
            import time
            health_report['timestamp'] = time.time()
            
            # Check database connection
            db_healthy = self.check_database_connection()
            health_report['checks']['database'] = {
                'status': 'healthy' if db_healthy else 'unhealthy',
                'details': 'Database connection is working' if db_healthy else 'Database connection failed'
            }
            
            # Check Redis connection
            redis_healthy = self.check_redis_connection()
            health_report['checks']['redis'] = {
                'status': 'healthy' if redis_healthy else 'unhealthy',
                'details': 'Redis connection is working' if redis_healthy else 'Redis connection failed'
            }
            
            # Check state manager
            state_health = self.check_state_manager_health()
            health_report['checks']['state_manager'] = state_health
            
            # Check all modules
            modules_health = self.check_all_modules_health()
            health_report['checks']['modules'] = modules_health
            
            # Determine overall status
            unhealthy_checks = [
                check for check in health_report['checks'].values()
                if check.get('status') in ['unhealthy', 'degraded']
            ]
            
            if unhealthy_checks:
                health_report['overall_status'] = 'degraded' if len(unhealthy_checks) < len(health_report['checks']) else 'unhealthy'
                health_report['unhealthy_components'] = [
                    component for component, check in health_report['checks'].items()
                    if check.get('status') in ['unhealthy', 'degraded']
                ]
            else:
                health_report['overall_status'] = 'healthy'
            
            custom_log(f"✅ Comprehensive health check completed: {health_report['overall_status']}")
            return health_report
            
        except Exception as e:
            custom_log(f"❌ Comprehensive health check failed: {e}", level="ERROR")
            health_report['overall_status'] = 'unhealthy'
            health_report['error'] = str(e)
            return health_report 