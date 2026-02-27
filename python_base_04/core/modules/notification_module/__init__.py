"""
Core notification module. Provides API for listing and marking messages,
and a service for other modules to create notifications (e.g. Dutch tournament invite).
"""

from .notification_main import NotificationMain
from .notification_service import NotificationService

__all__ = ['NotificationMain', 'NotificationService']
