import 'package:cleco/utils/consts/theme_consts.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../managers/services_manager.dart';
import 'ticker_timer.dart';

class TimerWidget extends StatefulWidget {
  final String timerKey; // Unique key for each timer instance
  final Duration duration;
  final VoidCallback callback;

  const TimerWidget({
    Key? key,
    required this.timerKey,
    required this.duration,
    required this.callback,
  }) : super(key: key);

  @override
  _TimerWidgetState createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  TickerTimer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);

    // Retrieve or register a new instance if not exists
    _tickerTimer = servicesManager.getService<TickerTimer>(widget.timerKey);
    if (_tickerTimer == null) {
      _tickerTimer = TickerTimer(id: widget.timerKey);
      servicesManager.registerService(widget.timerKey, _tickerTimer!);
    }

    _tickerTimer?.startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServicesManager>(
      builder: (context, servicesManager, child) {
        final timerService = servicesManager.getService<TickerTimer>(widget.timerKey);
        if (timerService == null) {
          return const Text("⚠ Timer service not found.");
        }

        int remainingTime = widget.duration.inSeconds - timerService.elapsedSeconds;
        if (remainingTime <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.callback();
          });
          return Text("⏳ Time's up!", style: AppTextStyles.headingMedium().copyWith(
            fontWeight: FontWeight.bold,
          ));
        }
        return Text("⏳ ${remainingTime}s", style: AppTextStyles.headingMedium());
      },
    );
  }

  @override
  void dispose() {
    _tickerTimer?.stopTimer();
    super.dispose();
  }
}
