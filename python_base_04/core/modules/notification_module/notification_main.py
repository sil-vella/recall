"""
Core notification module: registers API routes and exposes NotificationService
for other modules (e.g. Dutch game) to create notifications.
"""

from core.modules.base_module import BaseModule
from .notification_routes import notification_api, set_app_manager, register_response_handler
from .notification_service import NotificationService



class NotificationMain(BaseModule):
    """Core notification module. Owns list/mark-read API and NotificationService for in-process create."""

    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.dependencies = []
        self._notification_service = None

    def initialize(self, app_manager):
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self._notification_service = NotificationService(app_manager)
        set_app_manager(app_manager)
        self.register_routes()
        self._initialized = True

    def register_routes(self):
        if self.app:
            self.app.register_blueprint(notification_api)

    def get_notification_service(self) -> NotificationService:
        """Return the notification service for other modules to create notifications."""
        return self._notification_service

    def register_response_handler(self, source: str, handler):
        """Register a single response handler for the given source. Modules call this during init; handler(doc, action_identifier, user_id) receives full payload and dispatches by msg_id + action_identifier."""
        register_response_handler(source, handler)
