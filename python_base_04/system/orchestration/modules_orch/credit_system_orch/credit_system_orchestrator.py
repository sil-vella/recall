from system.orchestration.modules_orch.base_files.module_orch_base import ModuleOrchestratorBase
from tools.logger.custom_logging import custom_log
from typing import Dict, Any, Optional
from system.modules.credit_system_module.credit_system_main import CreditSystemModule
from flask import request, jsonify
from datetime import datetime


class CreditSystemOrchestrator(ModuleOrchestratorBase):
    """
    Orchestrator for CreditSystemModule.
    Handles system integration, lifecycle management, and request forwarding.
    """
    
    def __init__(self, manager_initializer):
        """
        Initialize the credit system orchestrator.
        
        Args:
            manager_initializer: ManagerInitializer instance for accessing all managers
        """
        super().__init__(manager_initializer)
        self.manager_initializer = manager_initializer
        self.module = None
        self.is_initialized = False
        custom_log("CreditSystemOrchestrator created")

    def initialize(self):
        """Initialize the orchestrator and module."""
        try:
            # Create module instance (no config needed - module accesses secrets directly)
            self.module = CreditSystemModule()
            
            # Initialize the module
            self.module.initialize()
            
            # Register hooks with the system
            self._register_hooks()
            
            self.is_initialized = True
            custom_log("✅ CreditSystemOrchestrator initialized successfully")
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize CreditSystemOrchestrator: {e}", level="ERROR")
            raise

    def _register_hooks(self):
        """Register module hooks with the system."""
        try:
            hooks_manager = self.manager_initializer.get_manager('hooks_manager')
            if hooks_manager:
                # Get hooks needed by the module
                hooks_needed = self.module.get_hooks_needed()
                
                for hook_info in hooks_needed:
                    event = hook_info['event']
                    priority = hook_info.get('priority', 10)
                    context = hook_info.get('context', 'credit_system')
                    
                    # Register the hook
                    hooks_manager.register_hook(
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

    def forward_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Forward a request to the credit system module.
        
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
            
            return self.module.forward_request(request_data)
            
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
                    'orchestrator': 'CreditSystemOrchestrator',
                    'error': 'Orchestrator not initialized'
                }
            
            # Get module health
            module_health = self.module.health_check()
            
            return {
                'status': module_health['status'],
                'orchestrator': 'CreditSystemOrchestrator',
                'module': module_health,
                'is_initialized': self.is_initialized
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'orchestrator': 'CreditSystemOrchestrator',
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
                'orchestrator': 'CreditSystemOrchestrator',
                'is_initialized': self.is_initialized,
                'module_config': module_config
            }
            
        except Exception as e:
            return {
                'orchestrator': 'CreditSystemOrchestrator',
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

    def dispose(self):
        """Cleanup orchestrator resources."""
        try:
            if self.module:
                # Module doesn't have dispose method, but we can clean up references
                self.module = None
            
            self.is_initialized = False
            custom_log("CreditSystemOrchestrator disposed")
            
        except Exception as e:
            custom_log(f"❌ Error disposing orchestrator: {e}", level="ERROR") 