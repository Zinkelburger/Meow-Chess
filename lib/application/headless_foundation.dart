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

/// Equal by value through nested maps and lists, as JSON evidence is after
/// a save and reload.
bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && deepEquals(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

bool listEquals<T>(List<T>? a, List<T>? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => a[i] == b[i]));
