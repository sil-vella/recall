"""
Notification API routes: list messages, mark as read, and single response endpoint. JWT required.
Core knows only source: for source "core" it handles Close (delete doc); for other sources it passes
full payload (doc, action_identifier, user_id) to the registered callable. Modules dispatch by msg_id + action_identifier.
"""

from datetime import datetime

from flask import Blueprint, request, jsonify
from bson import ObjectId

from core.managers.jwt_manager import TokenType

from .notification_service import NOTIFICATIONS_COLLECTION
from .global_broadcast_service import (
    GLOBAL_BROADCAST_MESSAGES_COLL,
    insert_global_broadcast,
    mark_global_broadcasts_read,
)

notification_api = Blueprint("notification_api", __name__)

_app_manager = None

# Source reserved for core-built-in notifications (e.g. generic Close).
CORE_SOURCE = "core"
# Action for core source: close and delete the notification.
CORE_ACTION_CLOSE = "close"

# source -> callable(doc, action_identifier, user_id) -> dict. Module receives full payload and dispatches by msg_id + action_identifier.
_response_handlers = {}


def set_app_manager(app_manager):
    global _app_manager
    _app_manager = app_manager


def register_response_handler(source: str, handler):
    """
    Register a single response handler for a source. Called by modules during init.
    Core will call handler(normalized_doc, action_identifier, user_id); the module dispatches by doc["msg_id"] and action_identifier.
    :param source: Must match notification doc "source" (e.g. "dutch_game").
    :param handler: Callable(doc, action_identifier, user_id) -> dict (jsonified as response).
    """
    if not source or not callable(handler):
        return
    _response_handlers[source.strip()] = handler


def _require_admin():
    """If current user is not admin, return (response, status_code). Else return (None, None)."""
    if not request.user_id:
        return jsonify({"success": False, "error": "Not authenticated"}), 401
    if not _app_manager:
        return jsonify({"success": False, "error": "Server not initialized"}), 503
    db_manager = _app_manager.get_db_manager(role="read_only")
    if not db_manager:
        return jsonify({"success": False, "error": "Database unavailable"}), 503
    try:
        user_oid = ObjectId(request.user_id) if isinstance(request.user_id, str) else request.user_id
        user = db_manager.find_one("users", {"_id": user_oid})
    except Exception:
        user = None
    if not user or user.get("role") != "admin":
        return jsonify({"success": False, "error": "Admin role required"}), 403
    return None, None


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
        if not cursor:
            return jsonify({"success": True, "data": []}), 200
        items = list(cursor)[offset : offset + limit]
        out = []
        for doc in items:
            created = doc.get("created_at")
            read_at = doc.get("read_at")
            _id = doc.get("_id")
            responses = doc.get("responses")
            if not isinstance(responses, list):
                responses = []
            responses_out = []
            for r in (responses or []):
                if not isinstance(r, dict):
                    continue
                label = (r.get("label") or "").strip()
                action_id = (r.get("action_identifier") or r.get("action") or "").strip()
                if label and action_id:
                    responses_out.append({"label": label, "action_identifier": action_id})
            out.append({
                "id": str(_id) if _id is not None else None,
                "msg_id": doc.get("msg_id") or "",
                "source": doc.get("source", ""),
                "type": doc.get("type", ""),
                "subtype": doc.get("subtype", ""),
                "title": doc.get("title", ""),
                "body": doc.get("body", ""),
                "data": doc.get("data") or {},
                "responses": responses_out,
                "created_at": created.isoformat() if isinstance(created, datetime) else created,
                "read": doc.get("read", False) is True,
                "read_at": read_at.isoformat() if isinstance(read_at, datetime) else read_at,
            })
        return jsonify({"success": True, "data": out}), 200
    except Exception as e:
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
        return jsonify({"success": True, "updated": updated}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


def _doc_to_dict(doc):
    """Build a serializable dict from a notification document for handler(doc, action_identifier, user_id)."""
    if not doc:
        return {}
    created = doc.get("created_at")
    read_at = doc.get("read_at")
    return {
        "id": str(doc["_id"]) if doc.get("_id") else None,
        "msg_id": doc.get("msg_id") or "",
        "user_id": str(doc["user_id"]) if doc.get("user_id") else None,
        "source": doc.get("source", ""),
        "type": doc.get("type", ""),
        "subtype": doc.get("subtype", ""),
        "title": doc.get("title", ""),
        "body": doc.get("body", ""),
        "data": doc.get("data") if isinstance(doc.get("data"), dict) else {},
        "responses": list(doc.get("responses") or []),
        "read": bool(doc.get("read")),
        "created_at": created.isoformat() if isinstance(created, datetime) else created,
        "read_at": read_at.isoformat() if isinstance(read_at, datetime) else read_at,
    }


@notification_api.route("/userauth/notifications/response", methods=["POST"])
def handle_response():
    """
    Single endpoint for all notification response actions. Body: message_id, action_identifier.
    For source "core", action "close": delete the notification and return success.
    For other sources: pass full payload (doc, action_identifier, user_id) to the registered handler; module dispatches by msg_id + action_identifier.
    """
    try:
        user_id = _get_current_user_id()
        if not user_id:
            return jsonify({"success": False, "error": "Unauthorized"}), 401
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not configured"}), 500
        data = request.get_json(silent=True) or {}
        message_id = (data.get("message_id") or "").strip()
        action_identifier = (data.get("action_identifier") or data.get("action") or "").strip().lower()
        if not message_id or not action_identifier:
            return jsonify({"success": False, "error": "message_id and action_identifier required"}), 400
        try:
            msg_oid = ObjectId(message_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid message_id"}), 400
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 500
        doc = db_manager.find_one(NOTIFICATIONS_COLLECTION, {"_id": msg_oid})
        if not doc:
            return jsonify({"success": False, "error": "Notification not found"}), 404
        doc_user_id = doc.get("user_id")
        if str(doc_user_id) != str(user_id):
            return jsonify({"success": False, "error": "Forbidden"}), 403
        source = (doc.get("source") or "").strip()
        if not source:
            return jsonify({"success": False, "error": "Notification has no source"}), 400

        # Core-built-in: source "core", action "close" -> delete doc and return success
        if source == CORE_SOURCE and action_identifier == CORE_ACTION_CLOSE:
            try:
                db_manager.delete(
                    NOTIFICATIONS_COLLECTION,
                    {"_id": msg_oid, "user_id": doc_user_id},
                )
            except Exception:
                pass
            return jsonify({"success": True, "message": "Closed"}), 200

        # Other sources: pass full payload to registered handler
        handler = _response_handlers.get(source)
        if not handler or not callable(handler):
            return jsonify({"success": False, "error": "No handler registered for source"}), 400
        normalized_doc = _doc_to_dict(doc)
        try:
            result = handler(normalized_doc, action_identifier, user_id)
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500
        if not isinstance(result, dict):
            return jsonify({"success": False, "error": "Invalid handler result"}), 500
        if result.get("success") is True:
            now = datetime.utcnow()
            try:
                db_manager.update(
                    NOTIFICATIONS_COLLECTION,
                    {"_id": msg_oid, "user_id": doc_user_id},
                    {"read": True, "read_at": now, "updated_at": now},
                )
            except Exception:
                pass
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@notification_api.route("/userauth/notifications/global-mark-read", methods=["POST"])
def global_mark_read():
    """Mark global broadcast(s) as read for the current user. Body: { "global_message_ids": ["<ObjectId>", ...] }."""
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
        raw_ids = data.get("global_message_ids") or data.get("message_ids") or []
        if not isinstance(raw_ids, list):
            return jsonify({"success": False, "error": "global_message_ids must be a list"}), 400
        capped = [str(x) for x in raw_ids if x][:50]
        updated = mark_global_broadcasts_read(db_manager, user_id, capped)
        return jsonify({"success": True, "updated": updated}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@notification_api.route("/userauth/notifications/admin/global-broadcast", methods=["POST"])
def admin_create_global_broadcast():
    """Admin only: create a document in global_broadcast_messages. Body matches insert_global_broadcast fields."""
    err = _require_admin()
    if err[0] is not None:
        return err
    try:
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not configured"}), 500
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 500
        data = request.get_json(silent=True) or {}
        if not isinstance(data, dict):
            return jsonify({"success": False, "error": "JSON body required"}), 400
        inserted = insert_global_broadcast(db_manager, data)
        if not inserted:
            return jsonify({"success": False, "error": "Invalid payload or insert failed"}), 400
        return jsonify({"success": True, "id": inserted, "collection": GLOBAL_BROADCAST_MESSAGES_COLL}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
