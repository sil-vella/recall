"""
ModuleOrchestratorBase

Base class for all module orchestrators. Provides access to all core managers via the ManagerInitializer.
"""

class ModuleOrchestratorBase:
    """
    Base class for all module orchestrators.
    Stores a reference to the ManagerInitializer, which provides access to all core managers.
    Manages and initializes all module orchestrators explicitly.
    """

    def __init__(self, manager_initializer):
        """
        Args:
            manager_initializer (ManagerInitializer): Gives access to all core managers.
        """
        self.manager_initializer = manager_initializer
        self.orchestrators = {}  # Registry for module orchestrators
        
        # Store commonly used managers for easy access
        self._store_common_managers()

    def _store_common_managers(self):
        """Store commonly used managers as instance variables for easy access."""
        try:
            self.hooks_manager = self.manager_initializer.app_initializer.hooks_manager
            self.db_manager = self.manager_initializer.db_manager
            self.jwt_manager = self.manager_initializer.jwt_manager
            self.state_manager = self.manager_initializer.state_manager
            self.redis_manager = self.manager_initializer.redis_manager
        except AttributeError as e:
            # Managers might not be initialized yet, store as None
            self.hooks_manager = None
            self.db_manager = None
            self.jwt_manager = None
            self.state_manager = None
            self.redis_manager = None

    def initialize_orchestrators(self):
        """
        Manually instantiate and register all module orchestrators here.
        Add new orchestrators as needed.
        Calls initialize() on each orchestrator after instantiation.
        """
        try:
            from system.orchestration.modules_orch.credit_system_orch.credit_system_orchestrator import CreditSystemOrchestrator
            self.orchestrators['credit_system'] = CreditSystemOrchestrator(self.manager_initializer)
        except ImportError:
            # If the orchestrator does not exist yet, skip
            pass
            
        try:
            from system.orchestration.modules_orch.user_management_orch.user_management_orchestrator import UserManagementOrchestrator
            self.orchestrators['user_management'] = UserManagementOrchestrator(self.manager_initializer)
        except ImportError:
            # If the orchestrator does not exist yet, skip
            pass

        try:
            from system.orchestration.modules_orch.in_app_purchases_orch.in_app_purchases_orchestrator import InAppPurchasesOrchestrator
            self.orchestrators['in_app_purchases'] = InAppPurchasesOrchestrator(self.manager_initializer)
        except ImportError:
            # If the orchestrator does not exist yet, skip
            pass

        try:
            from system.orchestration.modules_orch.stripe_orch.stripe_orchestrator import StripeOrchestrator
            self.orchestrators['stripe'] = StripeOrchestrator(self.manager_initializer)
        except ImportError:
            # If the orchestrator does not exist yet, skip
            pass

        # Call initialize on each orchestrator
        for orch in self.orchestrators.values():
            if hasattr(orch, 'initialize'):
                orch.initialize()

    def get_orchestrator(self, key):
        """
        Retrieve a module orchestrator by key.
        """
        return self.orchestrators.get(key) 