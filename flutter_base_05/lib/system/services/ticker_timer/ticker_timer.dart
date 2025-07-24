import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../../../tools/logging/logger.dart';
import '../../00_base/service_base.dart';

class TickerTimer extends ServicesBase with ChangeNotifier {
  static final Logger _log = Logger();

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
    _log.info('✅ TickerTimer [$id] initialized.');
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
    _log.info('▶ Timer [$id] resumed from ${_pausedDuration.inSeconds}s.');
  }

  void pauseTimer() {
    if (!_isRunning || _isPaused) return;

    _isPaused = true;
    _ticker?.stop();
    _pausedDuration = Duration(seconds: _elapsedSeconds); // ✅ Save elapsed time
    notifyListeners();
    _log.info('⏸ Timer [$id] paused at ${_pausedDuration.inSeconds}s.');
  }


  void stopTimer() {
    if (!_isRunning) return;

    _ticker?.stop();
    _isRunning = false;
    _isPaused = false;
    _pausedDuration = Duration.zero;
    notifyListeners();
    _log.info('⏹ Timer [$id] stopped.');
  }

  void resetTimer() {
    stopTimer();
    _elapsedSeconds = 0;
    notifyListeners();
    _log.info('🔄 Timer [$id] reset.');
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}
