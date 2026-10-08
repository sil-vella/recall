# Server maintenance instant modal

**Status:** Completed

## Objective

Show players a maintenance notice when the Dart server sends `server_maintenance`, using the existing instant-message modal (`NotificationsModule.addPendingWsInstant` → `InstantMessageModal`).

## Steps

- [x] Map `server_maintenance` to an `instant_ws` payload (title + server message as body)
- [x] Register and unregister the WebSocket listener with the other core events

## Files modified

- `flutter_base_05/lib/core/managers/websockets/ws_event_handler.dart`
- `flutter_base_05/lib/core/managers/websockets/ws_event_listener.dart`
- `Documentation/VPS/DR_UPDATE_PIPELINE.md`

## Notes

The modal uses the default OK button. Response buttons are omitted so dismiss does not depend on a response handler. This ships in the next app build; the backend event is already live.

Task Manager sync skipped: `TASK_MANAGER_BASE_URL`, `TASK_MANAGER_SLUG`, `TM_USERNAME`, or `TM_PASSWORD` was not set in `.env.local` or `.env.prod`.
