# Notification System

Core notification system: backend API, Flutter client, and app-wide instant modals.

---

## Overview

- **Backend**: Python `notification_module` — REST API (list messages, mark-read) and `NotificationService` for in-process creation by other modules.
- **Client**: Flutter `NotificationsModule` (fetch/cache, markAsRead) and `InstantMessageModal` (instant-type modals app-wide).
- **Integration**: `BaseScreen` shows instant notifications on any screen; mark-as-read on any modal close (OK, response button, or back).
- **Database**: `notifications` collection; mark-read uses encrypted query for `user_id` (database_manager encrypts update/delete queries).

---

## Backend (Python)

- **Module**: `python_base_04/core/modules/notification_module/`
- **NotificationService.create(user_id, source, type, title, body, data?, responses?, subtype?)** — types: `instant`, `admin`, `advert`.
- **GET /userauth/notifications/messages** — query params: `limit`, `offset`, `unread_only`. JWT required.
- **POST /userauth/notifications/mark-read** — body `{ message_ids: [...] }`. JWT required. Same semantics as playbook 13: filter by `_id` + `user_id`, set `read`, `read_at`, `updated_at`.

Database manager must encrypt the update query (and convert `user_id` string to ObjectId) so mark-read matches stored documents.

---

## Flutter

- **NotificationsModule**: state key `notifications`; `fetchMessages()`, `markAsRead()`, `lastMessages`.
- **InstantMessageModal**: type `instant`; PopScope so any close runs `onMarkAsRead(id)` and `onDismiss()`; optional response buttons call `onSendResponse`.
- **BaseScreen**: after build, `_checkAndShowInstantMessages()` — throttled fetch, then `InstantMessageModal.showUnreadInstantModals()` with `onMarkAsRead` and `onSendResponse` (POST/GET to endpoint with `message_id`, `action`). On response success, triggers hook `instant_message_response_success`.

---

## Files

| Layer  | Path |
|--------|------|
| Python | `core/modules/notification_module/` (notification_main, notification_service, notification_routes) |
| Python | `core/managers/database_manager.py` (encrypt query in _execute_update, _execute_delete; user_id in _convert_string_to_objectid) |
| Python | `core/managers/module_registry.py`, `core/managers/app_manager.py` (notification_module, get_notification_service) |
| Flutter | `lib/modules/notifications_module/notifications_module.dart` |
| Flutter | `lib/core/widgets/instant_message_modal.dart` |
| Flutter | `lib/core/00_base/screen_base.dart` (_checkAndShowInstantMessages) |
| Flutter | `lib/core/managers/module_registry.dart` (notifications_module registration) |
