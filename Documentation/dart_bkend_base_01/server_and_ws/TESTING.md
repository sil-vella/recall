# Testing Guide

## Overview

This guide covers testing the Dart WebSocket server for the Dutch card game. It includes manual testing, automated testing, and integration testing approaches.

## Manual Testing

### 1. Browser Console Testing

#### Setup
1. Start the server: `dart run app.dart`
2. Open browser developer console
3. Connect to WebSocket server

#### Basic Connection Test
```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = () => {
  console.log('✅ Connected to server');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('📩 Received:', data);
};

ws.onerror = (error) => {
  console.error('❌ Connection error:', error);
};

ws.onclose = () => {
  console.log('👋 Connection closed');
};
```

#### Ping/Pong Test
```javascript
// Send ping
ws.send(JSON.stringify({event: 'ping'}));

// Expected response:
// {event: "pong", timestamp: "2025-10-28T12:53:54.015292"}
```

#### Room Creation Test
```javascript
// Create room
ws.send(JSON.stringify({
  event: 'create_room',
  user_id: 'test_player_123'
}));

// Expected response:
// {event: "room_created", room_id: "room_1761652434996", creator_id: "test_player_123"}
```

#### Room Joining Test
```javascript
// Join room (use room_id from previous response)
ws.send(JSON.stringify({
  event: 'join_room',
  room_id: 'room_1761652434996',
  user_id: 'test_player_456'
}));

// Expected responses:
// {event: "room_joined", room_id: "room_1761652434996", user_id: "test_player_456"}
// {event: "player_joined", room_id: "room_1761652434996", user_id: "test_player_456", player_count: 2}
```

#### Room Listing Test
```javascript
// List all rooms
ws.send(JSON.stringify({event: 'list_rooms'}));

// Expected response:
// {
//   event: "rooms_list",
//   rooms: [{room_id: "room_1761652434996", creator_id: "test_player_123", player_count: 2, created_at: "2025-10-28T12:53:54.997387"}],
//   total: 1
// }
```

### 2. Multiple Client Testing

#### Test with Two Browser Windows
1. Open two browser windows
2. Run the connection code in both consoles
3. Create room in first window
4. Join room from second window
5. Verify both clients receive appropriate messages

#### Test Room Broadcasting
```javascript
// Client 1: Create room
ws1.send(JSON.stringify({event: 'create_room', user_id: 'player1'}));

// Client 2: Join room
ws2.send(JSON.stringify({event: 'join_room', room_id: 'room_123', user_id: 'player2'}));

// Both clients should receive:
// {event: "player_joined", room_id: "room_123", user_id: "player2", player_count: 2}
```

### 3. Error Testing

#### Invalid JSON Test
```javascript
// Send invalid JSON
ws.send('invalid json');

// Expected response:
// {event: "error", message: "Invalid message format"}
```

#### Missing Event Test
```javascript
// Send message without event
ws.send(JSON.stringify({data: 'some data'}));

// Expected response:
// {event: "error", message: "Missing event field"}
```

#### Unknown Event Test
```javascript
// Send unknown event
ws.send(JSON.stringify({event: 'unknown_event'}));

// Expected response:
// {event: "error", message: "Unknown event: unknown_event"}
```

#### Join Non-existent Room Test
```javascript
// Try to join non-existent room
ws.send(JSON.stringify({
  event: 'join_room',
  room_id: 'nonexistent_room',
  user_id: 'player123'
}));

// Expected response:
// {event: "error", message: "Failed to join room: nonexistent_room"}
```

## Automated Testing

### 1. Dart Test Client

#### Basic Test Client
```dart
import 'dart:io';
import 'dart:convert';

void main() async {
  print('🧪 Testing Dart Game Server WebSocket...');
  
  try {
    // Connect to WebSocket server
    final webSocket = await WebSocket.connect('ws://localhost:8080');
    print('✅ Connected to server');
    
    // Listen for messages
    webSocket.listen((message) {
      final data = jsonDecode(message);
      print('📩 Received: ${data['event']} - ${data['message'] ?? data.toString()}');
    });
    
    // Test ping
    print('📤 Sending ping...');
    webSocket.add(jsonEncode({'event': 'ping'}));
    await Future.delayed(Duration(seconds: 1));
    
    // Test room creation
    print('📤 Creating room...');
    webSocket.add(jsonEncode({
      'event': 'create_room',
      'user_id': 'test_user_123'
    }));
    await Future.delayed(Duration(seconds: 1));
    
    // Test room listing
    print('📤 Listing rooms...');
    webSocket.add(jsonEncode({'event': 'list_rooms'}));
    await Future.delayed(Duration(seconds: 1));
    
    // Close connection
    await webSocket.close();
    print('👋 Disconnected from server');
    
  } catch (e) {
    print('❌ Error: $e');
  }
}
```

#### Advanced Test Client
```dart
import 'dart:io';
import 'dart:convert';

class WebSocketTester {
  WebSocket? _webSocket;
  String? _sessionId;
  String? _roomId;
  
  Future<void> runTests() async {
    await _testConnection();
    await _testPing();
    await _testRoomCreation();
    await _testRoomJoining();
    await _testRoomListing();
    await _testErrorHandling();
    await _testDisconnection();
  }
  
  Future<void> _testConnection() async {
    print('🔌 Testing connection...');
    _webSocket = await WebSocket.connect('ws://localhost:8080');
    
    _webSocket!.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'connected') {
        _sessionId = data['session_id'];
        print('✅ Connection test passed');
      }
    });
    
    await Future.delayed(Duration(seconds: 1));
  }
  
  Future<void> _testPing() async {
    print('🏓 Testing ping/pong...');
    bool pongReceived = false;
    
    _webSocket!.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'pong') {
        pongReceived = true;
        print('✅ Ping/pong test passed');
      }
    });
    
    _webSocket!.add(jsonEncode({'event': 'ping'}));
    await Future.delayed(Duration(seconds: 1));
    
    if (!pongReceived) {
      print('❌ Ping/pong test failed');
    }
  }
  
  Future<void> _testRoomCreation() async {
    print('🏠 Testing room creation...');
    bool roomCreated = false;
    
    _webSocket!.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'room_created') {
        _roomId = data['room_id'];
        roomCreated = true;
        print('✅ Room creation test passed');
      }
    });
    
    _webSocket!.add(jsonEncode({
      'event': 'create_room',
      'user_id': 'test_user_123'
    }));
    
    await Future.delayed(Duration(seconds: 1));
    
    if (!roomCreated) {
      print('❌ Room creation test failed');
    }
  }
  
  Future<void> _testRoomJoining() async {
    if (_roomId == null) {
      print('❌ Room joining test skipped (no room ID)');
      return;
    }
    
    print('👥 Testing room joining...');
    bool roomJoined = false;
    
    _webSocket!.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'room_joined') {
        roomJoined = true;
        print('✅ Room joining test passed');
      }
    });
    
    _webSocket!.add(jsonEncode({
      'event': 'join_room',
      'room_id': _roomId,
      'user_id': 'test_user_456'
    }));
    
    await Future.delayed(Duration(seconds: 1));
    
    if (!roomJoined) {
      print('❌ Room joining test failed');
    }
  }
  
  Future<void> _testRoomListing() async {
    print('📋 Testing room listing...');
    bool roomsListed = false;
    
    _webSocket!.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'rooms_list') {
        roomsListed = true;
        print('✅ Room listing test passed');
      }
    });
    
    _webSocket!.add(jsonEncode({'event': 'list_rooms'}));
    
    await Future.delayed(Duration(seconds: 1));
    
    if (!roomsListed) {
      print('❌ Room listing test failed');
    }
  }
  
  Future<void> _testErrorHandling() async {
    print('⚠️ Testing error handling...');
    bool errorReceived = false;
    
    _webSocket!.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'error') {
        errorReceived = true;
        print('✅ Error handling test passed');
      }
    });
    
    // Send invalid message
    _webSocket!.add('invalid json');
    
    await Future.delayed(Duration(seconds: 1));
    
    if (!errorReceived) {
      print('❌ Error handling test failed');
    }
  }
  
  Future<void> _testDisconnection() async {
    print('👋 Testing disconnection...');
    await _webSocket!.close();
    print('✅ Disconnection test passed');
  }
}

void main() async {
  final tester = WebSocketTester();
  await tester.runTests();
}
```

### 2. Unit Tests

#### Test File Structure
```
test/
├── websocket_server_test.dart
├── room_manager_test.dart
├── message_handler_test.dart
└── integration_test.dart
```

#### WebSocket Server Test
```dart
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../lib/server/websocket_server.dart';

void main() {
  group('WebSocketServer', () {
    late WebSocketServer server;
    
    setUp(() {
      server = WebSocketServer();
    });
    
    test('should initialize with zero connections', () {
      expect(server.connectionCount, equals(0));
    });
    
    test('should handle connection', () {
      // Mock WebSocket channel
      final mockChannel = MockWebSocketChannel();
      server.handleConnection(mockChannel);
      
      expect(server.connectionCount, equals(1));
    });
  });
}

class MockWebSocketChannel extends WebSocketChannel {
  @override
  Stream<dynamic> get stream => Stream.empty();
  
  @override
  void sink.add(dynamic data) {
    // Mock implementation
  }
}
```

#### Room Manager Test
```dart
import 'package:test/test.dart';
import '../lib/server/room_manager.dart';

void main() {
  group('RoomManager', () {
    late RoomManager roomManager;
    
    setUp(() {
      roomManager = RoomManager();
    });
    
    test('should create room', () {
      final roomId = roomManager.createRoom('session_123', 'player456');
      
      expect(roomId, startsWith('room_'));
      expect(roomManager.roomCount, equals(1));
    });
    
    test('should join room', () {
      final roomId = roomManager.createRoom('session_123', 'player456');
      final success = roomManager.joinRoom(roomId, 'session_789', 'player789');
      
      expect(success, isTrue);
      expect(roomManager.getSessionsInRoom(roomId).length, equals(2));
    });
    
    test('should handle room not found', () {
      final success = roomManager.joinRoom('nonexistent_room', 'session_123', 'player456');
      
      expect(success, isFalse);
    });
    
    test('should destroy empty room', () {
      final roomId = roomManager.createRoom('session_123', 'player456');
      roomManager.leaveRoom('session_123');
      
      expect(roomManager.roomCount, equals(0));
    });
  });
}
```

## Integration Testing

### 1. Multi-Client Testing

#### Test Script
```dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';

class MultiClientTester {
  final List<WebSocket> _clients = [];
  final List<String> _sessionIds = [];
  
  Future<void> runMultiClientTest() async {
    print('🧪 Running multi-client integration test...');
    
    // Create 3 clients
    for (int i = 0; i < 3; i++) {
      await _createClient(i);
    }
    
    // Test room creation and joining
    await _testRoomOperations();
    
    // Test broadcasting
    await _testBroadcasting();
    
    // Cleanup
    await _cleanup();
  }
  
  Future<void> _createClient(int index) async {
    final client = await WebSocket.connect('ws://localhost:8080');
    _clients.add(client);
    
    client.listen((message) {
      final data = jsonDecode(message);
      if (data['event'] == 'connected') {
        _sessionIds.add(data['session_id']);
        print('✅ Client $index connected: ${data['session_id']}');
      }
    });
    
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<void> _testRoomOperations() async {
    print('🏠 Testing room operations...');
    
    // Client 0 creates room
    _clients[0].add(jsonEncode({
      'event': 'create_room',
      'user_id': 'player_0'
    }));
    
    await Future.delayed(Duration(seconds: 1));
    
    // Clients 1 and 2 join room
    for (int i = 1; i < 3; i++) {
      _clients[i].add(jsonEncode({
        'event': 'join_room',
        'room_id': 'room_123', // Use actual room ID from response
        'user_id': 'player_$i'
      }));
    }
    
    await Future.delayed(Duration(seconds: 2));
  }
  
  Future<void> _testBroadcasting() async {
    print('📢 Testing broadcasting...');
    
    // All clients should receive broadcast messages
    for (final client in _clients) {
      client.listen((message) {
        final data = jsonDecode(message);
        if (data['event'] == 'player_joined') {
          print('📩 Broadcast received: ${data['user_id']} joined');
        }
      });
    }
    
    await Future.delayed(Duration(seconds: 1));
  }
  
  Future<void> _cleanup() async {
    print('🧹 Cleaning up...');
    for (final client in _clients) {
      await client.close();
    }
    print('✅ Multi-client test completed');
  }
}

void main() async {
  final tester = MultiClientTester();
  await tester.runMultiClientTest();
}
```

### 2. Load Testing

#### Simple Load Test
```dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';

class LoadTester {
  final int _clientCount = 100;
  final List<WebSocket> _clients = [];
  
  Future<void> runLoadTest() async {
    print('🚀 Running load test with $_clientCount clients...');
    
    // Create clients
    for (int i = 0; i < _clientCount; i++) {
      await _createClient(i);
    }
    
    print('✅ All clients connected');
    
    // Send messages concurrently
    await _sendConcurrentMessages();
    
    // Cleanup
    await _cleanup();
  }
  
  Future<void> _createClient(int index) async {
    final client = await WebSocket.connect('ws://localhost:8080');
    _clients.add(client);
    
    if (index % 10 == 0) {
      print('Connected $index clients...');
    }
  }
  
  Future<void> _sendConcurrentMessages() async {
    print('📤 Sending concurrent messages...');
    
    final futures = <Future>[];
    for (int i = 0; i < _clientCount; i++) {
      futures.add(_sendMessages(_clients[i], i));
    }
    
    await Future.wait(futures);
  }
  
  Future<void> _sendMessages(WebSocket client, int index) async {
    for (int i = 0; i < 10; i++) {
      client.add(jsonEncode({
        'event': 'ping',
        'client_id': index,
        'message_id': i
      }));
      
      await Future.delayed(Duration(milliseconds: 10));
    }
  }
  
  Future<void> _cleanup() async {
    print('🧹 Cleaning up...');
    for (final client in _clients) {
      await client.close();
    }
    print('✅ Load test completed');
  }
}

void main() async {
  final tester = LoadTester();
  await tester.runLoadTest();
}
```

## Performance Testing

### 1. Connection Limits

#### Test Maximum Connections
```dart
import 'dart:io';
import 'dart:convert';

void main() async {
  print('🔍 Testing maximum connections...');
  
  final clients = <WebSocket>[];
  int connectedCount = 0;
  
  try {
    for (int i = 0; i < 1000; i++) {
      final client = await WebSocket.connect('ws://localhost:8080');
      clients.add(client);
      connectedCount++;
      
      if (i % 100 == 0) {
        print('Connected $connectedCount clients...');
      }
    }
    
    print('✅ Maximum connections test passed: $connectedCount clients');
    
  } catch (e) {
    print('❌ Connection limit reached at $connectedCount clients: $e');
  } finally {
    // Cleanup
    for (final client in clients) {
      await client.close();
    }
  }
}
```

### 2. Message Throughput

#### Test Message Rate
```dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  print('📊 Testing message throughput...');
  
  final client = await WebSocket.connect('ws://localhost:8080');
  int messagesSent = 0;
  int messagesReceived = 0;
  
  client.listen((message) {
    messagesReceived++;
  });
  
  final stopwatch = Stopwatch()..start();
  
  // Send messages as fast as possible
  Timer.periodic(Duration(milliseconds: 1), (timer) {
    if (stopwatch.elapsedMilliseconds < 5000) { // 5 seconds
      client.add(jsonEncode({'event': 'ping', 'id': messagesSent}));
      messagesSent++;
    } else {
      timer.cancel();
      stopwatch.stop();
      
      print('📤 Messages sent: $messagesSent');
      print('📩 Messages received: $messagesReceived');
      print('⏱️ Time: ${stopwatch.elapsedMilliseconds}ms');
      print('📊 Rate: ${messagesSent / (stopwatch.elapsedMilliseconds / 1000)} messages/second');
      
      client.close();
    }
  });
}
```

## Test Automation

### 1. Continuous Integration

#### GitHub Actions Workflow
```yaml
name: WebSocket Server Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Dart
      uses: dart-lang/setup-dart@v1
      with:
        sdk-version: '3.0.0'
    
    - name: Install dependencies
      run: dart pub get
    
    - name: Run tests
      run: dart test
    
    - name: Start server
      run: dart run app.dart &
    
    - name: Wait for server
      run: sleep 5
    
    - name: Run integration tests
      run: dart run test/integration_test.dart
```

### 2. Test Scripts

#### Run All Tests
```bash
#!/bin/bash
echo "🧪 Running WebSocket Server Tests"

# Start server
echo "🚀 Starting server..."
dart run app.dart &
SERVER_PID=$!

# Wait for server to start
sleep 3

# Run tests
echo "📋 Running unit tests..."
dart test

echo "🔗 Running integration tests..."
dart run test/integration_test.dart

echo "🚀 Running load tests..."
dart run test/load_test.dart

# Cleanup
echo "🧹 Cleaning up..."
kill $SERVER_PID

echo "✅ All tests completed"
```

## Test Results Interpretation

### Success Criteria

1. **Connection Test**: All clients can connect successfully
2. **Ping/Pong Test**: Ping requests receive pong responses
3. **Room Operations**: Rooms can be created, joined, and left
4. **Broadcasting**: Messages are broadcast to all room members
5. **Error Handling**: Invalid messages receive appropriate error responses
6. **Disconnection**: Clean disconnection and cleanup

### Performance Benchmarks

- **Connection Time**: < 100ms per connection
- **Message Latency**: < 10ms for ping/pong
- **Throughput**: > 1000 messages/second
- **Memory Usage**: < 1MB per 100 connections
- **CPU Usage**: < 10% under normal load

### Common Issues

1. **Connection Refused**: Server not running or port blocked
2. **Timeout**: Server not responding to messages
3. **Memory Leak**: Connections not properly cleaned up
4. **Race Conditions**: Concurrent operations causing issues

---

*This testing guide provides comprehensive coverage of the WebSocket server functionality. Use these tests to ensure reliability and performance before deploying to production.*
