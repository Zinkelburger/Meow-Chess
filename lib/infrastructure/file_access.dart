import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/diagnostics.dart';

const _channel = MethodChannel('meow_chess/file_access');

/// Restore device-local grants before opening events or running folder backups.
/// A missing/unmounted volume must not prevent access to the remaining events.
Future<void> restoreFileAccess() async {
  if (defaultTargetPlatform != TargetPlatform.macOS) return;
  try {
    final failed = await _channel.invokeListMethod<String>('restore') ?? [];
    for (final path in failed) {
      Diagnostics.record(
        'restore file access',
        'unavailable',
        context: {'path': path},
      );
    }
  } catch (error, stack) {
    Diagnostics.record(
      'restore file access',
      'failed',
      error: error,
      stack: stack,
    );
  }
}

/// Save a native access grant separately from portable tournament data.
/// Failure to remember access does not turn a successful event save into a failure.
Future<bool> rememberFileAccess(String path) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) return true;
  try {
    await _channel.invokeMethod<void>('remember', path);
    return true;
  } catch (error, stack) {
    Diagnostics.record(
      'remember file access',
      'failed',
      error: error,
      stack: stack,
      context: {'path': path},
    );
    return false;
  }
}
