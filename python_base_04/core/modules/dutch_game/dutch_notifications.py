"""
Unified notification creation for the Dutch game module.
Single source name and consistent structure; all Dutch notifications go through create_notification.
"""

from typing import Any, Dict, List, Optional

# Source and subtypes: use these everywhere so they stay in sync with registered handlers.
DUTCH_GAME_SOURCE = "dutch_game"
SUBTYPE_INVITE = "dutch_invite"
SUBTYPE_ROOM_JOIN = "dutch_room_join"
SUBTYPE_MATCH_INVITE = "dutch_match_invite"

# Standard response maps (label + action_identifier). Handlers are registered for these action_identifiers.
INVITE_RESPONSES = [
    {"label": "Accept", "action_identifier": "accept"},
    {"label": "Decline", "action_identifier": "decline"},
]
ROOM_JOIN_RESPONSES = [
    {"label": "Join", "action_identifier": "join"},
]
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
    data: Optional[Dict[str, Any]] = None,
    responses: Optional[List[Dict[str, Any]]] = None,
    notification_type: str = "instant",
) -> Optional[str]:
    """
    Create a notification for the given user via the core notification service.
    Always uses DUTCH_GAME_SOURCE so the core can route responses to this module's handlers.

    :param app_manager: App manager (for getting notification_module).
    :param user_id: Target user ID (ObjectId string).
    :param subtype: One of SUBTYPE_* (e.g. SUBTYPE_INVITE, SUBTYPE_ROOM_JOIN).
    :param title: Short title.
    :param body: Message body.
    :param data: Optional payload (e.g. create_match_id, room_id).
    :param responses: Optional list of {"label", "action_identifier"}. Use INVITE_RESPONSES / ROOM_JOIN_RESPONSES for consistency.
    :param notification_type: Core type; default "instant".
    :return: Message id string, or None on failure.
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
        data=data if isinstance(data, dict) else {},
        responses=responses if isinstance(responses, list) else [],
        subtype=(subtype or "").strip(),
    )


# ---------------------------------------------------------------------------
# Example usage (call from api_endpoints or other Dutch game code)
# ---------------------------------------------------------------------------
#
# Invite (game invite with Accept/Decline):
#
#   from . import dutch_notifications
#
#   msg_id = dutch_notifications.create_notification(
#       app_manager,
#       user_id=target_user_id,
#       subtype=dutch_notifications.SUBTYPE_INVITE,
#       title="Game invite",
#       body=f"{inviter_username} invited you to play Dutch.",
#       data={
#           "inviter_user_id": inviter_user_id,
#           "inviter_username": inviter_username,
#           "create_match_id": create_match_id or None,
#       },
#       responses=dutch_notifications.INVITE_RESPONSES,
#   )
#
# Room ready (Join button; handler returns room_id):
#
#   msg_id = dutch_notifications.create_notification(
#       app_manager,
#       user_id=participant_user_id,
#       subtype=dutch_notifications.SUBTYPE_ROOM_JOIN,
#       title="Game ready",
#       body="The game room is ready. Tap Join to enter.",
#       data={"room_id": room_id},
#       responses=dutch_notifications.ROOM_JOIN_RESPONSES,
#   )
#
# Custom responses (same source; register handler for your action_identifier):
#
#   msg_id = dutch_notifications.create_notification(
#       app_manager,
#       user_id=user_id,
#       subtype="my_subtype",
#       title="Title",
#       body="Body.",
#       data={"key": "value"},
#       responses=[{"label": "Do it", "action_identifier": "do_it"}],
#   )
