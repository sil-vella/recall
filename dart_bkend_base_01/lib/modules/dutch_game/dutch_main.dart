// =============================================================================
// Dutch game module — public entry point
// =============================================================================
//
// This file is the single import target for the Dutch game backend module.
// It re-exports the implementation from backend_core so that:
//
//   1. There is only ONE place that registers hook callbacks (backend_core).
//   2. App entry points (e.g. WebSocketServer) import this file only, not
//      backend_core/dutch_game_main.dart directly.
//
// How hooks work with the server:
// ---------------------------------
//   • WebSocketServer creates HooksManager and calls _initializeHooks(), which
//     registers hook *names* only: room_created, room_joined, leave_room,
//     room_closed (no callbacks yet).
//   • WebSocketServer then instantiates DutchGameModule(server, roomManager, hooksManager).
//     That constructor runs _registerHooks() in backend_core/dutch_game_main.dart,
//     which registers the actual *callbacks* for those four hooks.
//   • When MessageHandler handles create_room / join_room / leave_room (or
//     RoomManager closes a room), it calls _server.triggerHook('room_created', data)
//     (or room_joined / leave_room / room_closed). HooksManager invokes the
//     callbacks registered by DutchGameModule (e.g. _onRoomCreated, _onRoomJoined).
//
// So: hook names are declared in WebSocketServer; hook callbacks are registered
// only in backend_core/dutch_game_main.dart, which is loaded via this re-export.
//
// Do not add a second class or hook registration here. Keep all logic in
// backend_core/dutch_game_main.dart.
//
// =============================================================================

export 'backend_core/dutch_game_main.dart';
