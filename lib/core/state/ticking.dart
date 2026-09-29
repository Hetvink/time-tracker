import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds [builder] every [period] while [active] — for live clocks and
/// running timers. Only this subtree rebuilds; no setState involved.
class Ticking extends StatefulWidget {
  final Duration period;
  final bool active;
  final WidgetBuilder builder;

  const Ticking({
    super.key,
    this.period = const Duration(seconds: 1),
    this.active = true,
    required this.builder,
  });

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  final _tick = ValueNotifier(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Ticking old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.period != widget.period) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = widget.active
        ? Timer.periodic(widget.period, (_) => _tick.value++)
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: _tick,
    builder: (context, _, _) => widget.builder(context),
  );
}
