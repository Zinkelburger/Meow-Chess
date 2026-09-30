import 'package:flutter/services.dart';

/// Files the operating system asks the app to open: a double-clicked .meow at
/// launch, or one double-clicked while the app is already running. The
/// desktop runners queue paths until [start] announces Dart is ready, so a
/// file named at startup and one forwarded later arrive the same way.
final class NativeFileRequests {
  NativeFileRequests({required this.open, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('meow_chess/file_open');

  final void Function(String path) open;
  final MethodChannel _channel;
  bool _disposed = false;

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') throw MissingPluginException(call.method);
      _receive(call.arguments);
    });
    try {
      _receive(await _channel.invokeMethod<Object?>('ready'));
    } on MissingPluginException {
      // Platforms without a native runner channel (tests, web).
    }
  }

  // One event is open at a time, so only the first file is used.
  void _receive(Object? paths) {
    if (_disposed || paths is! List) return;
    final first = paths
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .firstOrNull;
    if (first != null) open(first);
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
