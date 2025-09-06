from core.modules.base_module import BaseModule
from flask import jsonify
from typing import Dict, Any


class WalletModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the WalletModule."""
        super().__init__(app_manager)
        self.dependencies = ["communications_module", "user_management"]
        def initialize(self, app_manager):
        """Initialize the WalletModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.register_routes()
        
        # Register hooks for user events
        self._register_hooks()
        
        self._initialized = True
        def _register_hooks(self):
        """Register hooks for user-related events."""
        if self.app_manager:
            # Note: Wallet data is now embedded directly in user document during creation
            # No need for separate wallet hook callback
            def register_routes(self):
        """Register wallet-related routes."""
        self._register_route_helper("/wallet/info", self.wallet_info, methods=["GET"])
        } routes")

    def wallet_info(self):
        """Get wallet module information."""
        return jsonify({
            "module": "wallet",
            "status": "operational",
            "message": "Wallet module is running in simplified mode"
        })

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for WalletModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        health_status['details'] = {'simplified_mode': True}
        return health_status 