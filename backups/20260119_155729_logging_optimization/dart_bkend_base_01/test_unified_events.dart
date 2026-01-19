#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';

void main() async {
  print('🧪 Testing Dart WebSocket Server with Unified Event Handling...');
  
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
    print('📤 Testing ping...');
    webSocket.add(jsonEncode({'event': 'ping'}));
    await Future.delayed(Duration(seconds: 1));
    
    // Test room creation
    print('📤 Testing room creation...');
    webSocket.add(jsonEncode({
      'event': 'create_room',
      'user_id': 'test_user_123'
    }));
    await Future.delayed(Duration(seconds: 1));
    
    // Test game events
    print('📤 Testing game events...');
    final gameEvents = [
      'start_match',
      'draw_card',
      'play_card',
      'discard_card',
      'take_from_discard',
      'call_dutch',
      'same_rank_play',
      'jack_swap',
      'queen_peek',
      'completed_initial_peek'
    ];
    
    for (final event in gameEvents) {
      print('📤 Testing $event...');
      webSocket.add(jsonEncode({
        'event': event,
        'game_id': 'room_123',
        'card_id': 'card_456',
        'token': 'test_token'
      }));
      await Future.delayed(Duration(milliseconds: 200));
    }
    
    // Test authentication
    print('📤 Testing authentication...');
    webSocket.add(jsonEncode({
      'event': 'create_room',
      'token': 'invalid_token',
      'user_id': 'test_user_456'
    }));
    await Future.delayed(Duration(seconds: 1));
    
    // Test unknown event
    print('📤 Testing unknown event...');
    webSocket.add(jsonEncode({'event': 'unknown_event'}));
    await Future.delayed(Duration(seconds: 1));
    
    // Close connection
    await webSocket.close();
    print('👋 Disconnected from server');
    
  } catch (e) {
    print('❌ Error: $e');
  }
}
