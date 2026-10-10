import 'diagnostics.dart';

/// Minimal notification support for the standalone Dart command adapter.
/// Flutter adapters mix in Flutter's ChangeNotifier over the same core commands.
class ChangeNotifier {
  final _listeners = <void Function()>[];
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Calls every listener. Like Flutter's ChangeNotifier, a listener that
  /// throws is logged and the rest still run: notification follows a
  /// committed save, so it must not turn that success into a failure.
  void notifyListeners() {
    for (final listener in List.of(_listeners)) {
      if (!_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (error, stack) {
        Diagnostics.record(
          'notify listeners',
          'failed',
          context: {'notifier': '$runtimeType'},
          error: error,
          stack: stack,
        );
      }
    }
  }

  void dispose() => _listeners.clear();
}

bool mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && a[key] == b[key]));

bool listEquals<T>(List<T>? a, List<T>? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.length == b.length &&
        Iterable.generate(a.length).every((i) => a[i] == b[i]));
