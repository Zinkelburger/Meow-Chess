import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'artifact_file.dart';
import 'save_location.dart';

const _channel = MethodChannel('meow_chess/artifact_file');

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
  final path = await _channel.invokeMethod<String>(
    'stagingDirectory',
    destination,
  );
  if (path == null || !p.isAbsolute(path)) {
    throw const FileSystemException('Could not prepare the report for saving.');
  }
  final staging = Directory(path);
  try {
    final file = File(p.join(path, 'complete'));
    file.writeAsBytesSync(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      flush: true,
    );
    validateArtifactDestination(destination);
    await _channel.invokeMethod<void>('publish', {
      'source': file.path,
      'destination': destination,
    });
  } finally {
    staging.deleteSync(recursive: true);
  }
}
