import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../application/diagnostics.dart';

/// Returns only a destination accepted by the native save dialog, including
/// its replacement confirmation. Cancellation leaves the destination alone.
Future<FileSaveLocation?> chooseSaveLocation({
  required String suggestedName,
}) async {
  final FileSaveLocation? location;
  if (defaultTargetPlatform == TargetPlatform.linux) {
    // file_selector_linux does not enable GTK's overwrite confirmation.
    final path = await const MethodChannel(
      'meow_chess/file_save',
    ).invokeMethod<String>('save', suggestedName);
    location = path == null ? null : FileSaveLocation(path);
  } else {
    location = await getSaveLocation(suggestedName: suggestedName);
  }
  if (location == null) {
    Diagnostics.record('save dialog', 'cancelled');
    return null;
  }
  // Never interpret a malformed native result relative to the launch folder.
  if (!p.isAbsolute(location.path)) {
    Diagnostics.record(
      'save dialog',
      'invalid destination',
      context: {'path': location.path},
    );
    throw const FormatException(
      'The save dialog did not return a full file path.',
    );
  }
  Diagnostics.record(
    'save dialog',
    'accepted',
    context: {'path': location.path},
  );
  return location;
}
