from system.modules.base_module import BaseModule
from tools.logger.custom_logging import custom_log
from flask import jsonify
from typing import Dict, Any


class WalletModule(BaseModule):
    def __init__(self, app_initializer=None):
        """Initialize the WalletModule."""
        super().__init__(app_initializer)
        self.dependencies = ["communications_module", "user_management"]
        custom_log("WalletModule created")

    def initialize(self, app_initializer):
        """Initialize the WalletModule with AppInitializer."""
        self.app_initializer = app_initializer
        self.app = app_initializer.flask_app
        self.register_routes()
        
        # Register hooks for user events
        self._register_hooks()
        
        self._initialized = True
        custom_log("WalletModule initialized")

    def _register_hooks(self):
        """Register hooks for user-related events."""
        if self.app_initializer:
            # Note: Wallet data is now embedded directly in user document during creation
            # No need for separate wallet hook callback
            custom_log("🎣 WalletModule: Wallet data embedded in user document - no hook callback needed")

    def register_routes(self):
        """Register wallet-related routes."""
        self._register_route_helper("/wallet/info", self.wallet_info, methods=["GET"])
        custom_log(f"WalletModule registered {len(self.registered_routes)} routes")

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