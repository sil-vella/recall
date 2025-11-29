import 'dart:async';

/// Timer manager for random join room delayed match starts
/// Tracks pending start timers and prevents duplicate starts
class RandomJoinTimerManager {
  static final RandomJoinTimerManager instance = RandomJoinTimerManager._internal();
  
  RandomJoinTimerManager._internal();

  /// Map of roomId -> Timer for pending match starts
  final Map<String, Timer> _timers = {};
  
  /// Map of roomId -> isStarting flag to prevent duplicate starts
  final Map<String, bool> _isStarting = {};

  /// Schedule a delayed match start for a room
  /// 
  /// [roomId] The room ID to schedule start for
  /// [delaySeconds] Delay in seconds before starting match
  /// [callback] Function to call when timer expires (receives roomId)
  void scheduleStartMatch(String roomId, int delaySeconds, Function(String) callback) {
    // Cancel existing timer if any
    cancelTimer(roomId);
    
    // Schedule new timer
    _timers[roomId] = Timer(Duration(seconds: delaySeconds), () {
      _isStarting[roomId] = true;
      callback(roomId);
      cleanup(roomId);
    });
  }

  /// Cancel a pending timer for a room
  /// 
  /// [roomId] The room ID to cancel timer for
  void cancelTimer(String roomId) {
    _timers[roomId]?.cancel();
    _timers.remove(roomId);
  }

  /// Check if a timer is active for a room
  /// 
  /// [roomId] The room ID to check
  /// Returns true if timer is active, false otherwise
  bool isTimerActive(String roomId) {
    return _timers.containsKey(roomId);
  }

  /// Check if a match is currently starting for a room
  /// 
  /// [roomId] The room ID to check
  /// Returns true if match is starting, false otherwise
  bool isStarting(String roomId) {
    return _isStarting[roomId] == true;
  }

  /// Cleanup timer and state for a room
  /// 
  /// [roomId] The room ID to cleanup
  void cleanup(String roomId) {
    _timers.remove(roomId);
    _isStarting.remove(roomId);
  }

  /// Cleanup all timers and state (for shutdown)
  void cleanupAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _isStarting.clear();
  }
}

