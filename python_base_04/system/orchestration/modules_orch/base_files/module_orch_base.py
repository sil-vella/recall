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
        # Example for additional orchestrators:
        # from system.orchestration.modules_orch.user_management_orch.user_management_orchestrator import UserManagementOrchestrator
        # self.orchestrators['user_management'] = UserManagementOrchestrator(self.manager_initializer)

        # Call initialize on each orchestrator
        for orch in self.orchestrators.values():
            if hasattr(orch, 'initialize'):
                orch.initialize()

    def get_orchestrator(self, key):
        """
        Retrieve a module orchestrator by key.
        """
        return self.orchestrators.get(key) 