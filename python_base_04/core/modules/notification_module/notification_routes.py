"""
Notification API routes: list messages and mark as read. JWT required.
"""

from datetime import datetime

from flask import Blueprint, request, jsonify
from bson import ObjectId

from core.managers.jwt_manager import TokenType
from tools.logger.custom_logging import custom_log

from .notification_service import NOTIFICATIONS_COLLECTION

notification_api = Blueprint("notification_api", __name__)

_app_manager = None
LOGGING_SWITCH = False  # Trace list_messages for inbox debugging


def set_app_manager(app_manager):
    global _app_manager
    _app_manager = app_manager


def _get_current_user_id():
    """Validate JWT and return current user_id string, or None."""
    if not _app_manager:
        return None
    jwt_manager = getattr(_app_manager, "jwt_manager", None)
    if not jwt_manager:
        return None
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        return None
    token = auth_header[7:] if auth_header.startswith("Bearer ") else auth_header
    payload = jwt_manager.verify_token(token, TokenType.ACCESS)
    if not payload:
        return None
    return payload.get("user_id")


@notification_api.route("/userauth/notifications/messages", methods=["GET"])
def list_messages():
    """
    List notifications for the current user. Query params: limit (default 50), offset (default 0), unread_only (default true).
    When unread_only is true, only notifications with read_at null are returned (server-side filter so client gets only unread).
    Pass unread_only=false to include read notifications.
    """
    try:
        user_id = _get_current_user_id()
        if not user_id:
            return jsonify({"success": False, "error": "Unauthorized"}), 401
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not configured"}), 500
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 500
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid user"}), 400
        limit = min(int(request.args.get("limit", 50)), 100)
        offset = int(request.args.get("offset", 0))
        unread_only = request.args.get("unread_only", "true").lower() in ("true", "1", "yes")
        query = {"user_id": user_oid}
        if unread_only:
            query["read_at"] = None
        cursor = db_manager.find(NOTIFICATIONS_COLLECTION, query)
        if LOGGING_SWITCH:
            custom_log(
                f"list_messages: user_id={user_id} query_keys={list(query.keys())} raw_count={len(cursor) if cursor else 0}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        if not cursor:
            return jsonify({"success": True, "data": []}), 200
        items = list(cursor)[offset : offset + limit]
        if LOGGING_SWITCH:
            custom_log(
                f"list_messages: returning {len(items)} items (offset={offset} limit={limit})",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        out = []
        for doc in items:
            created = doc.get("created_at")
            read_at = doc.get("read_at")
            _id = doc.get("_id")
            responses = doc.get("responses")
            if not isinstance(responses, list):
                responses = []
            out.append({
                "id": str(_id) if _id is not None else None,
                "source": doc.get("source", ""),
                "type": doc.get("type", ""),
                "subtype": doc.get("subtype", ""),
                "title": doc.get("title", ""),
                "body": doc.get("body", ""),
                "data": doc.get("data") or {},
                "responses": [dict(r) for r in responses if isinstance(r, dict)],
                "created_at": created.isoformat() if isinstance(created, datetime) else created,
                "read": doc.get("read", False) is True,
                "read_at": read_at.isoformat() if isinstance(read_at, datetime) else read_at,
            })
        return jsonify({"success": True, "data": out}), 200
    except Exception as e:
        custom_log(f"notification list_messages error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


@notification_api.route("/userauth/notifications/mark-read", methods=["POST"])
def mark_read():
    """Mark one or more messages as read. Body: { "message_ids": ["id1", "id2"] }."""
    try:
        user_id = _get_current_user_id()
        if not user_id:
            return jsonify({"success": False, "error": "Unauthorized"}), 401
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not configured"}), 500
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 500
        data = request.get_json(silent=True) or {}
        message_ids = data.get("message_ids") or []
        if not isinstance(message_ids, list):
            return jsonify({"success": False, "error": "message_ids must be a list"}), 400
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid user"}), 400
        # Same semantics as playbook 13_mark_all_notifications_read: set read=true, read_at=now
        now = datetime.utcnow()
        update_payload = {"read": True, "read_at": now, "updated_at": now}
        updated = 0
        for mid in message_ids[:100]:
            if not mid:
                continue
            try:
                doc_id = ObjectId(mid)
            except Exception:
                if LOGGING_SWITCH:
                    custom_log(f"mark_read: skip invalid message_id={mid!r}", level="WARNING", isOn=LOGGING_SWITCH)
                continue
            # Filter: doc by _id and user_id (same as playbook filter by user; we also require _id for security)
            query = {"_id": doc_id, "user_id": user_oid}
            result = db_manager.update(
                NOTIFICATIONS_COLLECTION,
                query,
                update_payload,
            )
            if result:
                updated += 1
        if LOGGING_SWITCH:
            custom_log(
                f"mark_read: user_id={user_id} message_ids_count={len(message_ids)} updated={updated}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        return jsonify({"success": True, "updated": updated}), 200
    except Exception as e:
        custom_log(f"notification mark_read error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500
