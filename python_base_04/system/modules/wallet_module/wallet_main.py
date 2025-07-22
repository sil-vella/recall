from system.managers.database_manager import DatabaseManager
from tools.logger.custom_logging import custom_log
from flask import jsonify
from typing import Dict, Any


class WalletModule:
    def __init__(self, db_manager: DatabaseManager):
        self.db_manager = db_manager
        custom_log("WalletModule created with explicit dependencies")

    def initialize(self):
        # Initialization logic if needed
        pass

    def _register_hooks(self):
        """Register hooks for user-related events."""
        if self.db_manager:
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
        health_status = {} # No super().health_check() as BaseModule is removed
        health_status['dependencies'] = ["database_manager"] # Explicitly list dependencies
        health_status['details'] = {'simplified_mode': True}
        return health_status 