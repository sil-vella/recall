"""
Unified notification creation for the Dutch game module.
Single source name and consistent structure; all Dutch notifications go through create_notification.
"""

from typing import Any, Dict, List, Optional

# Source and subtypes: use these everywhere so they stay in sync with registered handlers.
DUTCH_GAME_SOURCE = "dutch_game"
SUBTYPE_MATCH_INVITE = "dutch_match_invite"

# Logical message id for match invite (admin tournaments flow). Used when creating notifications and when registering response handlers.
MSG_ID_MATCH_INVITE = "dutch_game_invite_to_match_001"

# Standard response map for match invite (label + action_identifier).
MATCH_INVITE_RESPONSES = [
    {"label": "Join", "action_identifier": "join"},
    {"label": "Decline", "action_identifier": "decline"},
]


def create_notification(
    app_manager,
    user_id: str,
    subtype: str,
    title: str,
    body: str,
    msg_id: Optional[str] = None,
    data: Optional[Dict[str, Any]] = None,
    responses: Optional[List[Dict[str, Any]]] = None,
    notification_type: str = "instant",
) -> Optional[str]:
    """
    Create a notification for the given user via the core notification service.
    Always uses DUTCH_GAME_SOURCE. Pass msg_id so response handlers can be mapped per message kind.

    :param app_manager: App manager (for getting notification_module).
    :param user_id: Target user ID (ObjectId string).
    :param subtype: One of SUBTYPE_* (e.g. SUBTYPE_INVITE, SUBTYPE_ROOM_JOIN).
    :param title: Short title.
    :param body: Message body.
    :param msg_id: Logical message id (e.g. MSG_ID_INVITE, MSG_ID_ROOM_JOIN). Must match registration in register_message_handlers.
    :param data: Optional payload (e.g. create_match_id, room_id).
    :param responses: Optional list of {"label", "action_identifier"}. Use INVITE_RESPONSES / ROOM_JOIN_RESPONSES for consistency.
    :param notification_type: Core type; default "instant".
    :return: Inserted document _id (DB id) as string, or None on failure.
    """
    if not app_manager:
        return None
    notification_module = app_manager.module_manager.get_module("notification_module")
    if not notification_module or not hasattr(notification_module, "get_notification_service"):
        return None
    notif_service = notification_module.get_notification_service()
    if not notif_service:
        return None
    return notif_service.create(
        user_id=user_id,
        source=DUTCH_GAME_SOURCE,
        type=notification_type,
        title=(title or "").strip(),
        body=(body or "").strip(),
        msg_id=(msg_id or "").strip() or None,
        data=data if isinstance(data, dict) else {},
        responses=responses if isinstance(responses, list) else [],
        subtype=(subtype or "").strip(),
    )


# ---------------------------------------------------------------------------
# Example usage (match invite from admin tournaments)
# ---------------------------------------------------------------------------
#
#   from . import dutch_notifications
#
#   dutch_notifications.create_notification(
#       app_manager,
#       user_id=user_id,
#       subtype=dutch_notifications.SUBTYPE_MATCH_INVITE,
#       title="Match invite",
#       body="You're invited to a match.",
#       msg_id=dutch_notifications.MSG_ID_MATCH_INVITE,
#       data={"match_id": match_id},
#       responses=dutch_notifications.MATCH_INVITE_RESPONSES,
#   )
