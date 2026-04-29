import 'package:flutter/widgets.dart';

import '../../../core/managers/state_manager.dart';
import '../../../tools/logging/logger.dart';

/// When true, logs each time a [DutchSliceBuilder] subtree rebuilds because the selected slice changed.
const bool LOGGING_SWITCH = true; // enable-logging-switch.mdc; set false after test

typedef DutchSliceSelector<T> = T Function(Map<String, dynamic> dutchGameState);
typedef DutchSliceEquals<T> = bool Function(T previous, T current);
typedef DutchSliceWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T selected,
  Widget? child,
);

/// Rebuilds only when the selected dutch_game slice changes.
///
/// This keeps high-level widgets stable while allowing fine-grained updates
/// for independent gameplay sections.
class DutchSliceBuilder<T> extends StatefulWidget {
  final DutchSliceSelector<T> selector;
  final DutchSliceWidgetBuilder<T> builder;
  final DutchSliceEquals<T>? equals;
  final Widget? child;

  const DutchSliceBuilder({
    super.key,
    required this.selector,
    required this.builder,
    this.equals,
    this.child,
  });

  @override
  State<DutchSliceBuilder<T>> createState() => _DutchSliceBuilderState<T>();
}

class _DutchSliceBuilderState<T> extends State<DutchSliceBuilder<T>> {
  final StateManager _stateManager = StateManager();
  final Logger _logger = Logger();
  late T _selected;
  int _sliceChangeCount = 0;

  @override
  void initState() {
    super.initState();
    _selected = _computeSelected();
    _stateManager.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant DutchSliceBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selector != widget.selector || oldWidget.equals != widget.equals) {
      _selected = _computeSelected();
    }
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _selected, widget.child);
  }

  void _onStateChanged() {
    if (!mounted) return;
    final next = _computeSelected();
    final areEqual = widget.equals ?? _defaultEquals;
    if (areEqual(_selected, next)) return;
    if (LOGGING_SWITCH) {
      _sliceChangeCount++;
      _logger.info(
        'DutchSliceBuilder: slice changed → setState #$_sliceChangeCount '
        'widget=${widget.runtimeType} key=${widget.key}',
      );
    }
    setState(() {
      _selected = next;
    });
  }

  T _computeSelected() {
    final dutch = _stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? const {};
    return widget.selector(dutch);
  }

  bool _defaultEquals(T previous, T current) {
    return _deepEquals(previous, current);
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;

    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }

    if (a is Set && b is Set) {
      if (a.length != b.length) return false;
      for (final value in a) {
        if (!b.contains(value)) return false;
      }
      return true;
    }

    if (a.runtimeType != b.runtimeType) return false;
    return a == b;
  }
}
