import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../00_base/service_base.dart';

class TickerTimer extends ServicesBase with ChangeNotifier {
  Ticker? _ticker;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  Duration _pausedDuration = Duration.zero;

  final String id; // Unique identifier for each instance

  TickerTimer({required this.id});

  int get elapsedSeconds => _elapsedSeconds;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;

  @override
  Future<void> initialize() async {
    // TickerTimer initialized
  }

  void startTimer() {
    if (_isRunning && !_isPaused) return; // ✅ Only return early if running and NOT paused

    _isRunning = true;
    _isPaused = false;

    _ticker ??= Ticker((elapsed) {
      _elapsedSeconds = (_pausedDuration + elapsed).inSeconds; // ✅ Continue from paused time
      notifyListeners();
    });

    _ticker?.start();
  }

  void pauseTimer() {
    if (!_isRunning || _isPaused) return;

    _isPaused = true;
    _ticker?.stop();
    _pausedDuration = Duration(seconds: _elapsedSeconds); // ✅ Save elapsed time
    notifyListeners();
  }


  void stopTimer() {
    if (!_isRunning) return;

    _ticker?.stop();
    _isRunning = false;
    _isPaused = false;
    _pausedDuration = Duration.zero;
    notifyListeners();
  }

  void resetTimer() {
    stopTimer();
    _elapsedSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}
