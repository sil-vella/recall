import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/config.dart';
import 'websocket_server.dart';

/// POST `/service/notify-inbox` (Python → Dart, [X-Service-Key]); ops routes; other requests → WebSocket upgrade.
Handler createHttpAndWebSocketHandler({
  required WebSocketServer wsServer,
  required void Function(WebSocketChannel) onWebSocket,
}) {
  final wsHandler = webSocketHandler((dynamic webSocket) {
    onWebSocket(webSocket as WebSocketChannel);
  });
  return (Request request) async {
    final path = request.requestedUri.path;
    if (request.method == 'POST' && path == '/service/notify-inbox') {
      return _handleNotifyInbox(request, wsServer);
    }
    if (request.method == 'POST' && path == '/service/ops/drain-mode') {
      return _handleOpsDrainMode(request, wsServer);
    }
    if (request.method == 'GET' && path == '/service/ops/drain-status') {
      return _handleOpsDrainStatus(request, wsServer);
    }
    return wsHandler(request);
  };
}

Response? _rejectInvalidServiceKey(Request request) {
  final headerKey = request.headers['x-service-key'] ?? '';
  final expected = Config.pythonServiceKey;
  if (expected.isEmpty || headerKey != expected) {
    return Response.forbidden(
      jsonEncode({'ok': false, 'error': 'invalid_service_key'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
  return null;
}

Future<Response> _handleNotifyInbox(Request request, WebSocketServer wsServer) async {
  try {
    final denied = _rejectInvalidServiceKey(request);
    if (denied != null) return denied;

    final body = await request.readAsString();
    if (body.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'empty_body'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'invalid_json'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final userId = map['user_id']?.toString().trim() ?? '';
    if (userId.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'user_id_required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final sent = wsServer.notifyInboxChangedForUser(userId);
    return Response.ok(
      jsonEncode({'ok': true, 'sessions_notified': sent}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (_) {
    return Response.internalServerError(
      body: jsonEncode({'ok': false, 'error': 'internal'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleOpsDrainMode(
  Request request,
  WebSocketServer wsServer,
) async {
  try {
    final denied = _rejectInvalidServiceKey(request);
    if (denied != null) return denied;

    final body = await request.readAsString();
    if (body.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'empty_body'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'invalid_json'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final enabled = map['enabled'] == true;
    wsServer.setDrainMode(enabled);
    return Response.ok(
      jsonEncode({
        'ok': true,
        'drain_mode': wsServer.drainMode,
        ...wsServer.drainStatusPayload(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (_) {
    return Response.internalServerError(
      body: jsonEncode({'ok': false, 'error': 'internal'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleOpsDrainStatus(
  Request request,
  WebSocketServer wsServer,
) async {
  try {
    final denied = _rejectInvalidServiceKey(request);
    if (denied != null) return denied;

    return Response.ok(
      jsonEncode(wsServer.drainStatusPayload()),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (_) {
    return Response.internalServerError(
      body: jsonEncode({'ok': false, 'error': 'internal'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
