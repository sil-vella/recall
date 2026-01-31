# WebSocket and JWT Flow

## Overview

How WebSocket connections are used and how JWT and service-key authentication are applied across Flutter, Dart backend, and Python.

---

## Flow Summary

```
Flutter (has JWT from LoginModule)
    → connect(wsUrl, { query: { token }, auth: { token } })
    → receives server "connected" { session_id }
    → emits once: { event: "authenticate", token: "<user JWT>" }
Dart backend
    → validates session via allowlist: only "authenticate" and "ping" allowed when unauthenticated
    → for "authenticate" + token: calls Python POST /service/auth/validate
        with X-Service-Key: <DART_BACKEND_SERVICE_KEY> and body { token: "<user JWT>" }
Python
    → middleware: validates X-Service-Key (DART_BACKEND_SERVICE_KEY)
    → handler: JWTManager.validate_token(token) → { valid, user_id, rank, level, ... }
Dart backend
    → on success: _authenticatedSessions[sessionId] = true, send "authenticated"
    → all other events (create_room, join_room, game events) require isSessionAuthenticated
```

---

## Service Key (Dart Backend → Python)

All Dart backend calls to Python **service** endpoints require the shared secret:

- **Config (Python)**: `DART_BACKEND_SERVICE_KEY` (file `dart_backend_service_key` or env); `ENABLE_DART_SERVICE_KEY_AUTH` (default true) to require the key.
- **Config (Dart)**: `Config.pythonServiceKey` (same value); `Config.usePythonServiceKey` (default true) to send the key.
- **Header**: `X-Service-Key: <key>` or `Authorization: Bearer <key>`.
- **Endpoints**: `POST /service/auth/validate` (JWT validation for WS), `POST /service/dutch/update-game-stats` (game stats after game end).

The Flutter frontend never calls `/service/*`; it uses JWT for `/userauth/*` and no auth for `/public/*`.

---

## Flutter

### Where JWT comes from

- **LoginModule** (`flutter_base_05/lib/modules/login_module/login_module.dart`):
  - `getCurrentToken()` – returns current JWT (access token).
  - `hasValidToken()` – checks if user has a valid token (used before WS init).

### WebSocket usage

- **WebSocketManager** (`flutter_base_05/lib/core/managers/websockets/websocket_manager.dart`):
  - `initialize()`: gets token via `LoginModule.getCurrentToken()`, then calls `NativeWebSocketAdapter.connect(Config.wsUrl, { query: { token }, auth: { token } })`.
  - Does **not** send token with every message; token is only used at connect and for the single `authenticate` emit.

- **NativeWebSocketAdapter** (`flutter_base_05/lib/core/managers/websockets/native_websocket_adapter.dart`):
  - After receiving server `connected` (with `session_id`), emits **once**: `emit('authenticate', { 'token': token })`.
  - Other events (create_room, join_room, game events) are sent via `emit(eventName, data)` with **no** token in payload; `sendCustomEvent` only adds `user_id` from login state.

### Listeners

- Listens for: `authenticated`, `authentication_failed`, `authentication_error` (e.g. in `ws_event_listener.dart` / `ws_event_handler.dart`).
- State: `WebSocketStateHelpers` / state validator update `is_authenticated` when `authenticated` is received.

---

## Dart backend

### WebSocket server (`dart_bkend_base_01/lib/server/websocket_server.dart`)

- **State**: `_authenticatedSessions[sessionId]` (bool), `_sessionToUser[sessionId]` (userId).
- **On connect**: Sends `connected` with `authenticated: false`; sets `_authenticatedSessions[sessionId] = false`.
- **On message** (`_onMessage`):
  - Token validation runs **only** when `data['event'] == 'authenticate'` and `data.containsKey('token')`. No token handling for other events.
  - **validateAndAuthenticate**: Calls Python `POST /service/auth/validate` with header `X-Service-Key: Config.pythonServiceKey` (when `Config.usePythonServiceKey` is true) and body `{ "token": token }`. On success: sets `_authenticatedSessions[sessionId] = true`, `_sessionToUser[sessionId] = userId`, sends `authenticated` to client. On failure: sends `authentication_failed` or `authentication_error`.

### Message handler (`dart_bkend_base_01/lib/server/message_handler.dart`)

- **Allowlist for unauthenticated sessions**: Only these **incoming** events are allowed without auth:
  - `ping` – client ping (server replies with `pong`).
  - `authenticate` – client sends JWT; server validates via Python `/service/auth/validate` (with X-Service-Key) and marks session authenticated.
- **`pong`**: Not an incoming client event; server sends `pong` in response to `ping`. No need to allow it.
- **All other events** (room/game): `create_room`, `join_room`, `leave_room`, `list_rooms`, `join_random_game`, `start_match`, `draw_card`, `play_card`, etc. Require `_server.isSessionAuthenticated(sessionId)`. If not authenticated, handler sends error and returns without processing.

### Python API client (`dart_bkend_base_01/lib/services/python_api_client.dart`)

- **validateToken(token)**: `POST $baseUrl/service/auth/validate` with headers `Content-Type: application/json` and (when `Config.usePythonServiceKey` and key set) `X-Service-Key: Config.pythonServiceKey`; body `{ "token": token }`. Returns `{ valid, user_id, rank, level, account_type, username, ... }`.
- **updateGameStats(gameResults)**: `POST $baseUrl/service/dutch/update-game-stats` with same headers (including X-Service-Key when enabled); body `{ "game_results": gameResults }`. Used after a game ends.

---

## Python

### Service validate endpoint (`python_base_04/core/modules/dutch_game/api_endpoints.py`)

- **Route**: `POST /service/auth/validate` (service key required via app_manager middleware).
- **Auth**: Middleware checks `X-Service-Key` or `Authorization: Bearer <key>` against `Config.DART_BACKEND_SERVICE_KEY`; if `Config.ENABLE_DART_SERVICE_KEY_AUTH` is false, key is not required (testing only).
- **Body**: `{ "token": "<user JWT>" }`.
- **Logic**: `_validate_token_impl()` – `JWTManager().validate_token(token)`. On success loads user from DB (rank, level, account_type, username) and returns `{ valid: True, user_id, rank, level, account_type, username }`. On failure returns 400/401 with `{ valid: False, error }`.

### Legacy public validate endpoint

- **Route**: `POST /api/auth/validate` (public; no service key).
- Same body and logic as `/service/auth/validate`. Kept for backward compatibility; Dart backend uses `/service/auth/validate` with X-Service-Key.

### JWT manager (`python_base_04/core/managers/jwt_manager.py`)

- **validate_token(token, expected_type)**: Same as `verify_token` – decode JWT, check signature, exp, type, fingerprint (when applicable), revocation in Redis.
- **Token types**: ACCESS, REFRESH, WEBSOCKET. Validate endpoint uses default verification (verify_token with TokenType.ACCESS if needed).

### Route-based auth (`python_base_04/core/managers/app_manager.py`)

- Paths starting with `/service/`: require service key (unless `ENABLE_DART_SERVICE_KEY_AUTH` is false). Key from header `X-Service-Key` or `Authorization: Bearer <key>`; must equal `Config.DART_BACKEND_SERVICE_KEY`.

---

## Enforcement Summary

1. **Dart `websocket_server.dart`**: Run token validation only when `event == 'authenticate'` and `data.containsKey('token')`. Ignore `token` on all other events. Call Python `POST /service/auth/validate` with X-Service-Key and the user JWT.
2. **Dart `message_handler.dart`**: Allowlist `{ 'ping', 'authenticate' }` for unauthenticated sessions; reject all game/room events with a clear error when not authenticated.
3. **Python**: `/service/*` routes require X-Service-Key (configurable via `ENABLE_DART_SERVICE_KEY_AUTH`). Dart backend is the only caller of `/service/*`; Flutter uses JWT for `/userauth/*` and does not call `/service/*`.

---

**Last Updated**: 2026
