# Core Notification System — Reimplementation Note

This document describes the **core notification system** (non–tournament-specific) as implemented in the codebase before revert, for reimplementation after reverting to commit `de4569d8`.

---

## 1. Overview

- **Backend**: Python module `notification_module` with REST API (list messages, mark-read) and `NotificationService` for in-process creation by other modules.
- **Client**: Flutter `NotificationsModule` (fetch/cache, markAsRead) and `InstantMessageModal` (instant-type modals app-wide).
- **Integration**: `BaseScreen` shows instant notifications on any screen; mark-as-read on any modal close (OK, response button, or back).
- **Database**: `notifications` collection; mark-read must use **encrypted query** for `user_id` (same as find/insert) so updates match stored documents.

---

## 2. Python Backend

### 2.1 Module layout

- **Dir**: `python_base_04/core/modules/notification_module/`
- **Files**:
  - `__init__.py`: export `NotificationMain`, `NotificationService` (e.g. `__all__ = ['NotificationMain', 'NotificationService']`).
  - `notification_main.py`: `NotificationMain(BaseModule)` — in `initialize()` sets `_notification_service = NotificationService(app_manager)`, calls `set_app_manager(app_manager)`, `register_routes()` (registers blueprint). Exposes `get_notification_service()`.
  - `notification_routes.py`: `set_app_manager(app_manager)`; `_get_current_user_id()` (JWT from Authorization, verify via jwt_manager, return user_id). Blueprint `notification_api`.
  - `notification_service.py`: `NotificationService(app_manager)`, `NOTIFICATIONS_COLLECTION = "notifications"`, `NOTIFICATION_TYPE_*` and `NOTIFICATION_TYPES_PREDEFINED`.

### 2.2 NotificationService (notification_service.py)

- **create(user_id, source, type, title, body, data=None, responses=None, subtype=None)**:
  - Validate app_manager, db_manager; parse user_id to ObjectId.
  - Type: must be in `NOTIFICATION_TYPES_PREDEFINED` (`instant`, `admin`, `advert`); default `instant` if empty.
  - responses: keep only keys `label`, `endpoint`, `method`, `action` per item.
  - Document: `user_id` (ObjectId), `source`, `type`, `title`, `body`, `data` (dict or {}), `responses`, `subtype`, `read=False`, `read_at=None`, `created_at`, `updated_at` (now).
  - `db_manager.insert(NOTIFICATIONS_COLLECTION, doc)`; return inserted id string or None.

### 2.3 API routes (notification_routes.py)

- **GET /userauth/notifications/messages**
  - Auth: `_get_current_user_id()`; 401 if missing.
  - Query params: `limit` (default 50, max 100), `offset` (default 0), `unread_only` (default true).
  - Query: `{"user_id": user_oid}`; if unread_only add `"read_at": None`.
  - Use `db_manager.find(NOTIFICATIONS_COLLECTION, query)`, then slice `[offset:offset+limit]`.
  - Response: `{ success, data: [ { id, source, type, subtype, title, body, data, responses, created_at, read, read_at } ] }` (id = str(_id), dates as isoformat).

- **POST /userauth/notifications/mark-read**
  - Auth: same.
  - Body: `{ "message_ids": [id1, id2, ...] }`.
  - For each id in message_ids[:100]: convert to ObjectId, query `{"_id": doc_id, "user_id": user_oid}`, `db_manager.update(collection, query, {"read": True, "read_at": now, "updated_at": now})`; count updated.
  - Return `{ success, updated }`.

### 2.4 Module registration (Python)

- **ModuleRegistry** (module_registry.py): In `get_module_dependencies()`, include `"notification_module": []` and in `get_module_configuration()` include `"notification_module": { enabled: True, ... }`.
- **AppManager**: `get_notification_service()` returns `module_manager.get_module("notification_module").get_notification_service()` if present.
- Module key is **notification_module** (directory name); class from __init__ is **NotificationMain**.

---

## 3. Database manager (Python) — critical for mark-read

- **SENSITIVE_FIELDS**: Must include `user_id` so it is stored encrypted; queries must use the same encryption.
- **_convert_string_to_objectid(data)**:
  - Recursively convert: `_id` (str 24-char hex) → ObjectId; **user_id** (str 24-char hex) → ObjectId.
- **_execute_update(collection, query, data)**:
  - Convert query with `_convert_string_to_objectid(query)`.
  - **Encrypt query**: `encrypted_query = _encrypt_sensitive_fields(converted_query)` (so user_id in filter matches stored encrypted value).
  - Encrypt data: `_encrypt_sensitive_fields(data)`.
  - `update_many(encrypted_query, {'$set': encrypted_data})`; return modified_count.
- **_execute_delete(collection, query)**:
  - Same: convert query, then encrypt query, then delete_many(encrypted_query).

Without encrypting the update/delete query, mark-read matches 0 documents and notifications stay unread.

---

## 4. Flutter client

### 4.1 NotificationsModule (lib/modules/notifications_module/notifications_module.dart)

- Extends `ModuleBase`, key `notifications_module`, dependencies `['connections_api']` (or `connections_api_module` per existing registry).
- State key: `'notifications'`; initial state: `{ messages: [], unreadCount: 0, lastFetchedAt: null }`.
- **fetchMessages({ limit, offset, unreadOnly: true })**: GET `/userauth/notifications/messages?limit=...&offset=...&unread_only=...` via ConnectionsApiModule; on success update state with list, lastFetchedAt, unreadCount (from read_at null/empty).
- **markAsRead(messageIds)**: POST `/userauth/notifications/mark-read` body `{ message_ids: messageIds }`. On success update local state: set `read: true`, `read_at: now` for those ids in cached messages, recompute unreadCount.
- **lastMessages**: getter from state `messages`.

### 4.2 InstantMessageModal (lib/core/widgets/instant_message_modal.dart)

- Constant: `kNotificationTypeInstant = 'instant'`.
- **ResponseAction**: label, endpoint, method, action; `fromMessage(message)` builds list from `message['responses']` (only entries with label, endpoint, action).
- **InstantMessageModal**: message, onDismiss, dismissLabel, onSendResponse, onMarkAsRead.
  - **Single close path**: Wrap dialog in **PopScope**; on **onPopInvokedWithResult** when didPop, call **`_onInstantModalClosed()`** which: calls `onMarkAsRead(messageId)` (if id non-empty), then `onDismiss()`. So any close (OK, response button, system back) marks as read and dismisses.
  - OK button: just `Navigator.of(context).pop()`.
  - Response buttons: call `onSendResponse(endpoint, method, body: { message_id, action })`; on success pop; PopScope then runs _onInstantModalClosed (mark read + onDismiss).
- **show(context, message, onDismiss, dismissLabel, onSendResponse, onMarkAsRead)**: showDialog with barrierDismissible: false.
- **showUnreadInstantModals(context, messages, onMarkAsRead, onSendResponse)**:
  - Filter: type === instant, read_at null/empty, id non-empty, not in _shownIds.
  - For each: add id to _shownIds, show modal with onMarkAsRead and onSendResponse; mark-read only via PopScope on close (no duplicate after show).

### 4.3 BaseScreen (lib/core/00_base/screen_base.dart)

- After build (e.g. in initState or post-frame callback), call **`_checkAndShowInstantMessages()`**.
- **_checkAndShowInstantMessages()**:
  - If not logged in (login state isLoggedIn != true) return.
  - Get NotificationsModule; if null return.
  - Throttle: if lastFetchedAt exists and < 60s ago, use `mod.lastMessages`; else `await mod.fetchMessages()`.
  - Get ConnectionsApiModule for onSendResponse.
  - Call **InstantMessageModal.showUnreadInstantModals(context, messages: list, onMarkAsRead: (id) => mod.markAsRead([id]), onSendResponse: ...)**.
  - **onSendResponse**: POST or GET to endpoint with body (message_id, action); on success call `mod.markAsRead([msgId])` and trigger hook `instant_message_response_success` with context, subtype, response, message. Return success bool.

### 4.4 Module registry (Flutter)

- Register: `notifications_module` → NotificationsModule(), dependencies: `['connections_api']` (or as in existing module_registry.dart).

### 4.5 Other usages

- **messages_screen**: uses NotificationsModule for inbox list.
- **dutch_game_helpers**: may use NotificationsModule for fetching; no change to core notification behaviour.

---

## 5. Playbook alignment

- **playbooks/00_local/13_mark_all_notifications_read.py**: Updates notifications with `read: true`, `read_at: new Date()`. Backend mark-read must do the same: filter by user (+ _id per message), set read, read_at, updated_at. Database manager must encrypt the query so the filter matches stored docs.

---

## 6. Files to create or modify (reimplementation checklist)

**Python**

- `core/modules/notification_module/__init__.py`
- `core/modules/notification_module/notification_main.py`
- `core/modules/notification_module/notification_service.py`
- `core/modules/notification_module/notification_routes.py`
- `core/managers/module_registry.py` (add notification_module deps and config)
- `core/managers/app_manager.py` (get_notification_service)
- `core/managers/database_manager.py` (user_id in _convert_string_to_objectid; encrypt query in _execute_update and _execute_delete)

**Flutter**

- `lib/modules/notifications_module/notifications_module.dart`
- `lib/core/widgets/instant_message_modal.dart`
- `lib/core/00_base/screen_base.dart` (imports, _checkAndShowInstantMessages, call from build/initState)
- `lib/core/managers/module_registry.dart` (register NotificationsModule)

**Docs**

- `Documentation/Dutch_game/NOTIFICATION_SYSTEM.md` (overview; can be restored/updated from this note)

---

## 7. Summary

- **Backend**: Notification module with list + mark-read API; NotificationService.create for other modules; JWT on both endpoints.
- **DB**: Encrypt update/delete query (and convert user_id to ObjectId) so mark-read matches stored encrypted user_id.
- **Client**: NotificationsModule (fetch, markAsRead, state); InstantMessageModal with PopScope so every close runs mark-as-read + onDismiss; BaseScreen shows instant modals app-wide with throttled fetch and onSendResponse for server-defined actions.
