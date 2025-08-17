import 'package:flutter/material.dart';


import '../../../utils/recall_game_helpers.dart';

/// PendingGamesWidget - Shows available games that are created but not yet started
/// Fetches data on demand to avoid storing large lists in state
class PendingGamesWidget extends StatefulWidget {
  final String title;
  final Function(String) onJoinRoom;
  final String emptyMessage;

  const PendingGamesWidget({
    Key? key,
    this.title = 'Available Games',
    required this.onJoinRoom,
    this.emptyMessage = 'No pending games available',
  }) : super(key: key);

  @override
  _PendingGamesWidgetState createState() => _PendingGamesWidgetState();
}

class _PendingGamesWidgetState extends State<PendingGamesWidget> {
  
  List<Map<String, dynamic>> _pendingGames = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    // Don't auto-load on init - only load when user requests
  }

  /// Refresh pending games from server
  Future<void> _refreshPendingGames() async {
    if (_isLoading) return; // Prevent concurrent requests
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('🔄 Fetching pending games from server...');
      
      // Use validated event emitter to request pending games
      final result = await RecallGameHelpers.getPendingGames();

      if (result['success'] == true && result['data'] != null) {
        final roomsData = result['data'] as List<dynamic>?;
        if (roomsData != null && roomsData.isNotEmpty) {
          final games = roomsData
              .cast<Map<String, dynamic>>()
              .where((room) => room['permission'] == 'public')
              .toList();
          
          // Enhance with game tracking info
          final activeGames = RecallGameHelpers.getAllActiveGames();
          final enhancedGames = games.map((room) {
            final roomId = room['room_id'] as String?;
            final gameInfo = roomId != null ? activeGames[roomId] : null;
            
            return {
              ...room,
              'hasActiveGame': gameInfo != null,
              'gamePhase': gameInfo?['gamePhase'] ?? 'waiting',
              'gameStatus': gameInfo?['gameStatus'] ?? 'inactive',
              'lastGameUpdate': gameInfo?['lastUpdated'],
            };
          }).toList();
          
          setState(() {
            _pendingGames = enhancedGames;
            _lastRefresh = DateTime.now();
            _isLoading = false;
          });
          
          print('✅ Loaded ${_pendingGames.length} pending games');
        } else {
          // Empty list is OK - just means no games available
          setState(() {
            _pendingGames = [];
            _lastRefresh = DateTime.now();
            _isLoading = false;
          });
          print('✅ No pending games available');
        }
      } else {
        // Handle backend errors gracefully
        final errorMsg = result['error'] ?? 'Failed to fetch pending games';
        print('⚠️ Backend error: $errorMsg');
        
        setState(() {
          _pendingGames = [];
          _lastRefresh = DateTime.now();
          _isLoading = false;
          _error = 'Backend temporarily unavailable. Please try again later.';
        });
      }
    } catch (e) {
      print('❌ Error fetching pending games: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and refresh button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    if (_lastRefresh != null) ...[
                      Text(
                        'Updated: ${_formatTime(_lastRefresh!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      onPressed: _isLoading ? null : _refreshPendingGames,
                      icon: _isLoading 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      tooltip: 'Refresh pending games',
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Content area
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Error: $_error',
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_pendingGames.isEmpty && !_isLoading) ...[
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.games, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      _lastRefresh == null 
                          ? 'Tap refresh to load pending games'
                          : widget.emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ] else if (_isLoading && _pendingGames.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else ...[
              // Games list
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingGames.length,
                itemBuilder: (context, index) {
                  final game = _pendingGames[index];
                  final roomId = game['room_id']?.toString() ?? '';
                  final roomName = game['room_name'] ?? roomId;
                  final currentSize = game['current_size'] ?? 0;
                  final maxSize = game['max_size'] ?? 4;
                  final gamePhase = game['gamePhase'] ?? 'waiting';
                  final gameStatus = game['gameStatus'] ?? 'inactive';
                  final hasActiveGame = game['hasActiveGame'] == true;
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text('$roomName'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Players: $currentSize/$maxSize'),
                          if (game['permission'] == 'private')
                            const Text('🔒 Private', style: TextStyle(color: Colors.orange)),
                          // Game status indicator
                          if (hasActiveGame) ...[
                            Row(
                              children: [
                                Icon(
                                  gameStatus == 'active' ? Icons.play_circle : Icons.pause_circle,
                                  size: 16,
                                  color: gameStatus == 'active' ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Game: $gamePhase ($gameStatus)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: gameStatus == 'active' ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            const Row(
                              children: [
                                Icon(Icons.circle, size: 16, color: Colors.grey),
                                SizedBox(width: 4),
                                Text(
                                  'Waiting for players',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: currentSize < maxSize && gamePhase == 'waiting'
                            ? () => _joinRoom(roomId, roomName)
                            : null,
                        child: Text(
                          currentSize >= maxSize 
                              ? 'Full'
                              : gamePhase != 'waiting'
                                  ? 'Started'
                                  : 'Join',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            
            // Show loading overlay for refresh
            if (_isLoading && _pendingGames.isNotEmpty) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  /// Join a room
  void _joinRoom(String roomId, String roomName) {
    print('🚪 Joining room: $roomId ($roomName)');
    widget.onJoinRoom(roomId);
    
    // Optionally refresh the list after joining
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _refreshPendingGames();
      }
    });
  }

  /// Format time for display
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
