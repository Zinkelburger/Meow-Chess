import 'package:flutter/foundation.dart';

import 'artifact_file.dart';
import 'native_file_replacement.dart';
import 'save_location.dart';

/// Selects and safely publishes a report; null means the dialog was cancelled.
/// All GUI artifact saves go through this boundary, including diagnostic logs.
Future<String?> saveArtifact(String name, List<int> bytes) async {
  final location = await chooseSaveLocation(suggestedName: name);
  if (location == null) return null;
  await writeSelectedArtifact(location.path, bytes);
  return location.path;
}

/// Writes a file selected by the native save dialog, preserving its access grant.
Future<void> writeSelectedArtifact(String destination, List<int> bytes) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) {
    writeArtifact(destination, bytes);
    return;
  }
  validateArtifactDestination(destination);
  // NSSavePanel grants the selected file, not its parent. Foundation supplies
  // an accessible replacement directory on the destination volume instead.
  final staging = await NativeFileReplacement.prepare(destination);
  try {
    staging.file.writeAsBytesSync(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      flush: true,
    );
    validateArtifactDestination(destination);
    await staging.publish();
  } finally {
    staging.dispose();
  }
}
