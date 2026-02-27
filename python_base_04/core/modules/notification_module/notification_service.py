"""
Notification service: in-process API for other modules to create user notifications.
Used by Dutch game (tournament invite) and any other module that needs to notify users.
"""

from datetime import datetime
from typing import Any, Dict, List, Optional

from bson import ObjectId

from tools.logger.custom_logging import custom_log

NOTIFICATIONS_COLLECTION = "notifications"
LOGGING_SWITCH = False  # Set True to trace notification create (e.g. tournament invite)

# Core predefined types: modules must use one of these. Determines core behaviour (e.g. instant = modal).
NOTIFICATION_TYPE_INSTANT = "instant"
NOTIFICATION_TYPE_ADMIN = "admin"
NOTIFICATION_TYPE_ADVERT = "advert"
NOTIFICATION_TYPES_PREDEFINED = (NOTIFICATION_TYPE_INSTANT, NOTIFICATION_TYPE_ADMIN, NOTIFICATION_TYPE_ADVERT)


class NotificationService:
    """
    Creates notification documents for the core notifications collection.
    Other modules get this service via app_manager.get_notification_service() and call create().
    """

    def __init__(self, app_manager):
        self.app_manager = app_manager

    def create(
        self,
        user_id: str,
        source: str,
        type: str,
        title: str,
        body: str,
        data: Optional[Dict[str, Any]] = None,
        responses: Optional[List[Dict[str, Any]]] = None,
        subtype: Optional[str] = None,
    ) -> Optional[str]:
        """
        Create a notification for the given user. Inserts into the notifications collection.

        :param user_id: Target user ID (ObjectId string).
        :param source: Source module, e.g. "dutch_game".
        :param type: Core predefined type: one of NOTIFICATION_TYPES_PREDEFINED (instant, admin, advert). Drives core behaviour.
        :param title: Short title for the message.
        :param body: Body text.
        :param data: Optional extra payload (e.g. tournament_id).
        :param responses: Optional list of server-defined actions (label, endpoint, method, action). Module-defined for its subtype.
        :param subtype: Optional module-specific name (e.g. "tournament_invite") for the module's own handling and responses.
        :return: Inserted document _id as string, or None on failure.
        """
        if not self.app_manager:
            if LOGGING_SWITCH:
                custom_log("NotificationService.create: app_manager not set", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        db_manager = self.app_manager.get_db_manager(role="read_write")
        if not db_manager:
            if LOGGING_SWITCH:
                custom_log("NotificationService.create: db_manager not available", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            if LOGGING_SWITCH:
                custom_log(f"NotificationService.create: invalid user_id={user_id}", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        type_str = (type or "").strip()
        if type_str and type_str not in NOTIFICATION_TYPES_PREDEFINED:
            if LOGGING_SWITCH:
                custom_log(
                    f"NotificationService.create: type '{type_str}' not in predefined {NOTIFICATION_TYPES_PREDEFINED}; rejecting",
                    level="WARNING",
                    isOn=LOGGING_SWITCH,
                )
            return None
        if not type_str:
            type_str = NOTIFICATION_TYPE_INSTANT
        now = datetime.utcnow()
        responses_list = []
        if isinstance(responses, list):
            for r in responses:
                if isinstance(r, dict):
                    responses_list.append({k: v for k, v in r.items() if k in ("label", "endpoint", "method", "action")})
        doc = {
            "user_id": user_oid,
            "source": (source or "").strip(),
            "type": type_str,
            "title": (title or "").strip(),
            "body": (body or "").strip(),
            "data": data if isinstance(data, dict) else {},
            "responses": responses_list,
            "subtype": (subtype or "").strip(),
            "read": False,
            "read_at": None,
            "created_at": now,
            "updated_at": now,
        }
        try:
            msg_id = db_manager.insert(NOTIFICATIONS_COLLECTION, doc)
            if LOGGING_SWITCH:
                custom_log(
                    f"NotificationService.create: created notification for user={user_id} source={source} type={type} id={msg_id}",
                    level="INFO",
                    isOn=LOGGING_SWITCH,
                )
            return msg_id
        except Exception as e:
            custom_log(f"NotificationService.create: insert failed: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return None
