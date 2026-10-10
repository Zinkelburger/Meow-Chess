import 'package:flutter/widgets.dart';

/// Redraws a panel whenever the controller it shows changes, and follows the
/// panel to a different controller: the old one is let go, the new one is
/// listened to, and [controllerReplaced] lets the panel reload what it read
/// from the old one.
mixin ListensToController<T extends StatefulWidget> on State<T> {
  /// The controller [widget] shows. Read again whenever the widget changes.
  Listenable controllerOf(T widget);

  /// Runs when the controller notifies while the panel is mounted. Redraws
  /// by default.
  void controllerChanged() => setState(() {});

  /// Runs after the panel was handed a different controller, just before it
  /// rebuilds. Nothing to do by default.
  void controllerReplaced() {}

  void _notified() {
    if (mounted) controllerChanged();
  }

  @override
  void initState() {
    super.initState();
    controllerOf(widget).addListener(_notified);
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = controllerOf(oldWidget), after = controllerOf(widget);
    if (identical(before, after)) return;
    before.removeListener(_notified);
    after.addListener(_notified);
    controllerReplaced();
  }

  @override
  void dispose() {
    controllerOf(widget).removeListener(_notified);
    super.dispose();
  }
}
