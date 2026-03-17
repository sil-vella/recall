# Notification System — Complete Flow

End-to-end flow: core registration, types, how modules create messages and register response handlers, and how the frontend shows and handles them.

---

## 1. Core notification system (Python backend)

### 1.1 Module registration

- **Discovery**: `ModuleRegistry.get_modules()` scans `core/modules/` and loads each package. The folder `notification_module/` is discovered; its `__all__` exposes `NotificationMain`.
- **Module key**: `notification_module`.
- **Class**: `NotificationMain` (in `notification_main.py`) extends `BaseModule`.

### 1.2 Core module initialization

When the app starts, the module manager loads modules in dependency order. **NotificationMain.initialize(app_manager)**:

1. Creates **NotificationService(app_manager)** and keeps a reference.
2. Calls **set_app_manager(app_manager)** so routes can use JWT/DB.
3. **Registers the API blueprint** (`notification_api`) on the Flask app.

So the core owns:

- **NotificationService** — in-process API for other modules to create notifications.
- **REST API** — list messages, mark-read, single response endpoint.
- **Response handler registry** — `_response_handlers`: `source -> callable(doc, action_identifier, user_id)`. For source `"core"`, the core itself handles action `"close"` (delete doc). For other sources, the core passes the full payload to the registered callable; modules dispatch by `doc["msg_id"]` and `action_identifier`.

### 1.3 Predefined notification types (backend)

Defined in **notification_service.py**:

| Type       | Constant                    | Purpose |
|-----------|-----------------------------|---------|
| `instant` | NOTIFICATION_TYPE_INSTANT   | Shown as modal immediately; frontend polls and shows unread. |
| `admin`   | NOTIFICATION_TYPE_ADMIN     | Admin-style; core behaviour TBD. |
| `advert`  | NOTIFICATION_TYPE_ADVERT    | Advert-style; core behaviour TBD. |

**NOTIFICATION_TYPES_PREDEFINED** = `("instant", "admin", "advert")`.  
**NotificationService.create()** only accepts one of these; unknown types are rejected (or default to `instant` if type is empty).

Types drive **backend** semantics only. The frontend decides how to display based on `type` (e.g. `instant` → modal).

---

## 2. How modules register and use the core

### 2.1 Getting the notification service

Modules do **not** get a global singleton. They get the core **notification module** from the app, then the service:

```python
notification_module = app_manager.module_manager.get_module("notification_module")
notif_service = notification_module.get_notification_service()
```

So: **AppManager → ModuleManager → notification_module (NotificationMain) → get_notification_service() → NotificationService**.

### 2.2 Creating messages (modules “register” messages by creating them)

Modules create notifications by calling **NotificationService.create(...)**:

- **user_id** — target user (ObjectId string).
- **source** — module identifier, e.g. `"dutch_game"`, or `"core"` for core-built-in (e.g. generic Close).
- **type** — one of the core predefined types (`instant`, `admin`, `advert`).
- **title**, **body** — text.
- **msg_id** — optional logical message id (e.g. `"dutch_game_invite_to_match_001"`). Stored in the doc; returned in list/response. Modules use the same msg_id when registering response handlers so they can map **msg_id → action_identifier → handler**.
- **data** — optional dict (e.g. `room_id`, `match_id`).
- **responses** — optional list of `{"label": "...", "action_identifier": "..."}`. For source `"core"`, use `{"label": "Close", "action_identifier": "close"}` to get core’s built-in close (delete doc).
- **subtype** — optional module-specific name (e.g. `dutch_room_join`, `dutch_match_invite`).

The service inserts a document into the **notifications** collection (MongoDB). The document has both **\_id** (DB id, used as `message_id` in API) and **msg_id** (logical id for handler mapping).

### 2.3 Core-built-in: source `"core"` and action `"close"`

- **CORE_SOURCE** = `"core"`, **CORE_ACTION_CLOSE** = `"close"` (in `notification_routes.py`).
- If a notification has **source** `"core"` and the user taps the button with **action_identifier** `"close"`, the core **deletes** the document from the DB and returns `{"success": True, "message": "Closed"}`. No module handler is called.
- To create such a notification, use `source="core"` and `responses=[{"label": "Close", "action_identifier": "close"}]` (and optionally `msg_id` for display only).

### 2.4 Registering response handlers (other sources: full payload to module)

For **other sources**, the core only knows the **source**. When the client POSTs **message_id** and **action_identifier** to `/userauth/notifications/response`:

1. Core loads the notification by **message_id** (DB `_id`), checks ownership.
2. Reads **source** from the document.
3. If **source** is **"core"** and **action_identifier** is **"close"** → core deletes doc and returns success (see above).
4. Otherwise: looks up **one callable** per source: `handler = _response_handlers[source]`, then calls **handler(normalized_doc, action_identifier, user_id)**. The module’s handler receives the **full payload** (doc includes **msg_id**, **id**, **data**, etc.) and must dispatch by **msg_id** and **action_identifier** to its own handlers.

So modules **register a single dispatch function** per source, and internally maintain **msg_id → { action_identifier → callable(doc, user_id) }**:

```python
# Module keeps: msg_id -> { action_identifier -> callable(doc, user_id) }
_message_handlers = {}

def register_message_handlers(msg_id: str, handlers: dict):
    _message_handlers[msg_id] = { k: v for k, v in handlers.items() if k and callable(v) }

def _dutch_dispatch(doc, action_identifier: str, user_id: str):
    msg_id = (doc.get("msg_id") or "").strip()
    handlers = _message_handlers.get(msg_id)
    if not handlers: return {"success": False, "error": "No handlers for msg_id"}
    handler = handlers.get(action_identifier)
    if not handler: return {"success": False, "error": "Unknown action"}
    return handler(doc, user_id)

# At init: register each msg_id’s handlers, then register the single dispatch with core
register_message_handlers("dutch_game_invite_to_match_001", {"accept": ..., "decline": ..., "join": ...})
notification_module.register_response_handler("dutch_game", _dutch_dispatch)
```

When **creating** notifications, the module passes the same **msg_id** (e.g. `MSG_ID_MATCH_INVITE = "dutch_game_invite_to_match_001"`) so the dispatch can find the right handler.

---

## 3. Backend API flow (summary)

| Step | Who | What |
|------|-----|------|
| 1 | Module | Gets `NotificationService` via `get_module("notification_module").get_notification_service()`. |
| 2 | Module | Calls `notif_service.create(user_id, source, type, title, body, data, responses, subtype)` → doc inserted into `notifications` collection. |
| 3 | Client | GET `/userauth/notifications/messages?limit=&offset=&unread_only=` (JWT) → list of notifications for current user. |
| 4 | Client | POST `/userauth/notifications/mark-read` with `message_ids` to mark read. |
| 5 | Client | On response button tap: POST `/userauth/notifications/response` with `message_id`, `action_identifier`. |
| 6 | Core | Loads doc by message_id, checks user_id. If source is `"core"` and action is `"close"`: delete doc, return success. Else: call `_response_handlers[source](doc, action_identifier, user_id)`; module dispatches by doc["msg_id"] and action_identifier; on success core marks read. |

---

## 4. Frontend: notification types and display

### 4.0 Python backend types → how the frontend handles and shows them

The Python backend only creates notifications with type **`instant`**, **`admin`**, or **`advert`** (see notification_service.py). The frontend does **not** treat all three the same:

| Python type | Where it comes from | App-wide modal (popup) | Notifications list screen |
|-------------|---------------------|------------------------|----------------------------|
| **instant** | GET `/userauth/notifications/messages` (API) | **Yes.** When the message is unread, BaseScreen shows it in the **instant modal** (polling + throttle). User can tap response buttons; client calls POST `/userauth/notifications/response`. On close or response success, client marks read via API. | **Yes.** Same as every message: card with title, body, subtype, read state, date. Tap to mark read. |
| **admin** | Same API. | **No.** The frontend only shows a modal for type `instant` or `instant_ws`. Admin messages are **list-only**. | **Yes.** Shown in the list with the same card UI (title, body, subtype, read state). No special styling or section for “admin”. |
| **advert** | Same API. | **No.** List-only, like admin. | **Yes.** Same card in the list. No special styling for “advert”. |

So in practice:

- **instant** = “show as popup when unread” + “show in list”. Only this type triggers the app-wide instant modal from API messages.
- **admin** and **advert** = “show in list only”. They appear in the Notifications screen like any other message; the list does not branch on `type` (no different layout or icon per type). If you want different UI for admin/advert later (e.g. different icon or section), the frontend would need to branch on `m['type']` in the list builder.

### 4.1 Types (Flutter)

Defined in **instant_message_modal.dart** (and used by NotificationsModule / BaseScreen):

| Type constant | Value | Origin | Behaviour |
|---------------|--------|--------|-----------|
| kNotificationTypeInstant | `instant` | Python DB (NotificationService) | Fetched via GET messages; shown as modal when unread; mark-read and response via API. |
| kNotificationTypeInstantWs | `instant_ws` | Dart backend WebSocket event | Pushed by Dart backend via event `ws_instant_notification`; appended to pending list; shown as modal once; no API mark-read/response. |
| kNotificationTypeInstantFrontendOnly | `instant_frontend_only` | Flutter only | **Uses the same instant modal** as the other types. These messages are **not** fetched from the API; frontend modules call `InstantMessageModal.showFrontendOnlyInstant(context, ...)` directly when they need to show an instant modal (title, body, optional Close + Action). No backend, no list. |

### 4.2 Where notifications are fetched

- **From DB (Python API)**: **NotificationsModule.fetchMessages()** → GET `/userauth/notifications/messages` (ConnectionsApiModule). Used by the Notifications screen (list) and by BaseScreen for instant modals (polling + throttle).
- **From WebSocket (Dart backend)**: Listener for event **`ws_instant_notification`** → payload pushed to **NotificationsModule** “pending WS instants” list; BaseScreen drains this list and shows each as a modal (no fetch from DB for these).

### 4.3 Who shows modals and when

- **BaseScreen** (every screen that extends it):
  - On enter and every **kInstantNotificationPollSeconds** (20s) runs **\_checkAndShowInstantMessages()**.
  - First: **takePendingWsInstants()** → show each with **InstantMessageModal.show()** (no API).
  - Then: if throttle allows, **fetchMessages()** (or use cached **lastMessages**); **InstantMessageModal.showUnreadInstantModals()** for messages with type `instant` or `instant_ws` that are unread and not already in _shownIds.
- **Notifications screen**: On init and pull-to-refresh calls **fetchMessages(unreadOnly: false)** and shows the list (no modal).

### 4.4 Response button flow (DB-backed instant)

1. User taps a response button on an instant modal (message from DB).
2. **InstantMessageModal** calls **onSendResponse(messageId, actionIdentifier)** provided by BaseScreen.
3. BaseScreen sends POST `/userauth/notifications/response` with `message_id`, `action_identifier`.
4. On success, BaseScreen marks read locally and triggers **HooksManager.triggerHookWithData('instant_message_response_success', { context, msg_id, response, message })**. The hook payload uses **msg_id** (logical message id from the notification) so modules can map **msg_id → handler** on the frontend, same idea as backend.
5. **DutchEventManager** (or any module) registers on **instant_message_response_success** and routes by **data['msg_id']** to the right handler (e.g. `dutch_game_invite_to_match_001` for match-invite actions).

---

## 5. Dart backend: ws_instant_notification (instant_ws)

- **Event name**: `ws_instant_notification` (constant **kWsInstantNotificationEvent** in **websocket_server.dart**).
- **Sending**: Any code that has **WebSocketServer** and a **sessionId** can call **server.sendInstantNotification(sessionId, payload)**. Payload is a map (e.g. `title`, `body`, `data`, `responses`, `id`, `subtype`); the server sets **event: 'ws_instant_notification'** and sends it to that session.
- **Frontend**: **WSEventListener** registers a listener for `ws_instant_notification`; **WSEventHandler.handleWsInstantNotification(data)** pushes the payload into **NotificationsModule.addPendingWsInstant(payload)**. BaseScreen’s **\_checkAndShowInstantMessages()** drains **takePendingWsInstants()** and shows each with **InstantMessageModal.show()** (no mark-read or response API). So **instant_ws** is “show once as modal”; any custom behaviour for buttons would have to be implemented on the client or via another channel.

---

## 6. Frontend-only instant (instant_frontend_only)

- **Same instant modal**: `instant_frontend_only` uses the same **InstantMessageModal** as `instant` and `instant_ws`; only the source of the message differs.
- **Not from API**: These messages are **not** fetched from the API. Frontend modules call **InstantMessageModal.showFrontendOnlyInstant(context, …)** directly whenever they need to show an instant modal (e.g. a local confirmation or notice).
- **InstantMessageModal.showFrontendOnlyInstant(context, title, body, data?, actionLabel?, actionIdentifier?, onAction?)** builds a message with type **instant_frontend_only**, default responses **Close** and optionally **Action**, and shows it via the same modal. No backend call. If **onAction** is set, the optional button invokes it and the modal closes.

---

## 7. Dutch game module example (end-to-end)

### 7.1 Registration (init)

- **DutchGameMain.initialize()** gets **notification_module** and calls **api_endpoints.register_notification_handlers(notification_module)**.
- **register_notification_handlers** calls **register_message_handlers(MSG_ID_MATCH_INVITE, { accept, decline, join })** then **notification_module.register_response_handler("dutch_game", _dutch_dispatch)**. The core only sees one callable per source; _dutch_dispatch looks up doc["msg_id"] and action_identifier to run the right handler.

### 7.2 Creating notifications

- **dutch_notifications.create_notification(..., msg_id=..., ...)** gets the notification service and calls **notif_service.create(..., source=DUTCH_GAME_SOURCE, msg_id=msg_id, ...)**. **msg_id** is a logical id (e.g. **MSG_ID_MATCH_INVITE**) that matches the keys used in **register_message_handlers**. Subtypes and response lists (e.g. **MATCH_INVITE_RESPONSES**) define the buttons.

### 7.3 Response handling (backend)

- User taps “Join” on a room-ready notification → POST **/userauth/notifications/response** with that message’s id and **action_identifier: "join"**.
- Core loads the doc, sees **source=dutch_game**, calls **_dutch_dispatch** which looks up **doc["msg_id"]** and **action_identifier** and runs the registered handler (e.g. **_dutch_handle_join**).
- Client receives success; BaseScreen fires **instant_message_response_success** with **msg_id**, **response**, **message**, **context**. **DutchEventManager**’s routes by **msg_id** (e.g. `dutch_game_invite_to_match_001`) to run the right handler.

---

## 8. File reference

| Layer | File | Role |
|-------|------|------|
| Python | core/modules/notification_module/notification_main.py | NotificationMain: init, blueprint, get_notification_service, register_response_handlers. |
| Python | core/modules/notification_module/notification_service.py | NotificationService.create; NOTIFICATION_TYPES_PREDEFINED. |
| Python | core/modules/notification_module/notification_routes.py | list_messages, mark_read, handle_response; CORE_SOURCE/CORE_ACTION_CLOSE; register_response_handler(storage: source -> callable). |
| Python | core/modules/dutch_game/dutch_notifications.py | create_notification, DUTCH_GAME_SOURCE, SUBTYPE_MATCH_INVITE, MATCH_INVITE_RESPONSES. |
| Python | core/modules/dutch_game/api_endpoints.py | register_message_handlers(MSG_ID_MATCH_INVITE, ...), _dutch_dispatch, _dutch_handle_accept/decline/join; register_notification_handlers; invite_players_to_match creates match-invite notifications. |
| Python | core/modules/dutch_game/dutch_game_main.py | Gets notification_module, calls register_notification_handlers. |
| Flutter | lib/modules/notifications_module/notifications_module.dart | fetchMessages, markAsRead, lastMessages, addPendingWsInstant, takePendingWsInstants. |
| Flutter | lib/core/widgets/instant_message_modal.dart | Types; ResponseAction; show/showUnreadInstantModals/showFrontendOnlyInstant. |
| Flutter | lib/core/00_base/screen_base.dart | _checkAndShowInstantMessages: drain WS pending, fetch, showUnreadInstantModals, onSendResponse → API + hook. |
| Flutter | lib/core/managers/websockets/ws_event_listener.dart | Listener for ws_instant_notification. |
| Flutter | lib/core/managers/websockets/ws_event_handler.dart | handleWsInstantNotification → NotificationsModule.addPendingWsInstant. |
| Flutter | lib/modules/dutch_game/managers/dutch_event_manager.dart | instant_message_response_success hook → msg_id handlers. |
| Dart backend | lib/server/websocket_server.dart | kWsInstantNotificationEvent, sendInstantNotification(sessionId, payload). |

---

## 9. Summary diagram

```
[Module e.g. Dutch]
       │
       ├── get_module("notification_module") → get_notification_service()
       │         → notif_service.create(user_id, source, type, title, body, data, responses, subtype)
       │         → INSERT into notifications collection
       │
       └── register_response_handlers(source, { action_identifier: handler })
                 → stored in notification_routes._response_handlers

[Client]
       │
       ├── GET /userauth/notifications/messages → list (DB)
       ├── POST /userauth/notifications/mark-read
       ├── POST /userauth/notifications/response (message_id, action_identifier)
       │         → Core: load doc → _response_handlers[doc.source][action_identifier](doc, user_id) → return result, mark read
       │
       ├── WS event "ws_instant_notification" (Dart backend) → addPendingWsInstant → show modal once
       └── InstantMessageModal.showFrontendOnlyInstant(...) → show modal, no backend

[BaseScreen]
       └── _checkAndShowInstantMessages(): drain pending WS → show; fetch messages → showUnreadInstantModals
             → on response success → triggerHook('instant_message_response_success') → DutchEventManager etc.
```

This is the full flow from core registration and types, through modules registering messages (create) and responses (register_response_handlers), to the client fetching, showing modals, and handling button taps.
