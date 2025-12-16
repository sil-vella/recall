"""
Analytics Module Main

This module provides API endpoints for tracking and querying user analytics events.
"""

from core.modules.base_module import BaseModule
from core.services.analytics_service import AnalyticsService
from tools.logger.custom_logging import custom_log
from flask import request, jsonify
from datetime import datetime


class AnalyticsModule(BaseModule):
    """Module for tracking and querying user analytics events."""
    
    LOGGING_SWITCH = True
    
    def __init__(self, app_manager=None):
        """Initialize the AnalyticsModule."""
        super().__init__(app_manager)
        self.dependencies = ["user_management_module"]
        self.analytics_service = None
    
    def initialize(self, app_manager):
        """Initialize the AnalyticsModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        
        # Get or create analytics service
        self.analytics_service = app_manager.services_manager.get_service('analytics_service')
        if not self.analytics_service:
            # Create and register service if not already registered
            self.analytics_service = AnalyticsService(app_manager)
            app_manager.services_manager.register_service('analytics_service', self.analytics_service)
        
        self.register_routes()
        self._initialized = True
    
    def register_routes(self):
        """Register analytics routes."""
        # JWT authenticated route for tracking events (auth determined by /userauth/ prefix)
        self._register_auth_route_helper(
            "/userauth/analytics/track",
            self.track_event,
            methods=["POST"]
        )
        
        # JWT authenticated route for querying user events (optional, for debugging/admin)
        self._register_auth_route_helper(
            "/userauth/analytics/events",
            self.get_user_events,
            methods=["GET"]
        )
    
    def track_event(self):
        """Track a user event."""
        try:
            # Get user ID from JWT token (set by auth middleware)
            user_id = request.user_id
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "User not authenticated",
                    "message": "No user ID found in request"
                }), 401
            
            data = request.get_json()
            if not data:
                return jsonify({
                    "success": False,
                    "error": "Request body is required"
                }), 400
            
            event_type = data.get('event_type')
            if not event_type:
                return jsonify({
                    "success": False,
                    "error": "event_type is required"
                }), 400
            
            event_data = data.get('event_data', {})
            session_id = data.get('session_id')
            platform = data.get('platform')
            
            # Track event in MongoDB
            success = self.analytics_service.track_event(
                user_id=user_id,
                event_type=event_type,
                event_data=event_data,
                session_id=session_id,
                platform=platform
            )
            
            if success:
                # Update Prometheus metrics (optional - can track event counts)
                # For now, we'll rely on the detailed event storage
                custom_log(
                    f"AnalyticsModule: Tracked event - user_id: {user_id}, event_type: {event_type}",
                    level="DEBUG",
                    isOn=AnalyticsModule.LOGGING_SWITCH
                )
                
                return jsonify({
                    "success": True,
                    "message": "Event tracked successfully"
                }), 200
            else:
                return jsonify({
                    "success": False,
                    "error": "Failed to track event"
                }), 500
                
        except Exception as e:
            custom_log(f"AnalyticsModule: Error tracking event: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500
    
    def get_user_events(self):
        """Get user's event history (for debugging/admin purposes)."""
        try:
            # Get user ID from JWT token
            user_id = request.user_id
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "User not authenticated"
                }), 401
            
            # Get query parameters
            event_type = request.args.get('event_type')
            start_date_str = request.args.get('start_date')
            end_date_str = request.args.get('end_date')
            limit = int(request.args.get('limit', 100))
            
            # Parse dates if provided
            start_date = None
            end_date = None
            if start_date_str:
                try:
                    start_date = datetime.fromisoformat(start_date_str.replace('Z', '+00:00'))
                except Exception:
                    return jsonify({
                        "success": False,
                        "error": "Invalid start_date format (use ISO 8601)"
                    }), 400
            
            if end_date_str:
                try:
                    end_date = datetime.fromisoformat(end_date_str.replace('Z', '+00:00'))
                except Exception:
                    return jsonify({
                        "success": False,
                        "error": "Invalid end_date format (use ISO 8601)"
                    }), 400
            
            # Query events
            events = self.analytics_service.get_user_events(
                user_id=user_id,
                event_type=event_type,
                start_date=start_date,
                end_date=end_date,
                limit=limit
            )
            
            # Convert ObjectId to string for JSON serialization
            for event in events:
                if '_id' in event:
                    event['_id'] = str(event['_id'])
            
            return jsonify({
                "success": True,
                "events": events,
                "count": len(events)
            }), 200
            
        except Exception as e:
            custom_log(f"AnalyticsModule: Error getting user events: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500
    
    def health_check(self) -> dict:
        """Return module health status."""
        return {
            'module': 'analytics_module',
            'status': 'healthy' if self._initialized else 'not_initialized',
            'analytics_service_available': self.analytics_service is not None,
            'details': 'Analytics tracking module'
        }
