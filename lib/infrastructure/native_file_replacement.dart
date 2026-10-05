import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// A same-volume staging location granted by Foundation for a selected file.
/// The caller validates the destination and writes and flushes the complete file.
class NativeFileReplacement {
  NativeFileReplacement._(this.destination, this.directory);

  static const _channel = MethodChannel('meow_chess/artifact_file');
  final String destination;
  final Directory directory;
  File get file => File(p.join(directory.path, 'complete'));

  static Future<NativeFileReplacement> prepare(String destination) async {
    final path = await _channel.invokeMethod<String>(
      'stagingDirectory',
      destination,
    );
    if (path == null || !p.isAbsolute(path)) {
      throw const FileSystemException('Could not prepare the file for saving.');
    }
    return NativeFileReplacement._(destination, Directory(path));
  }

  Future<void> publish({bool replaceExisting = true}) =>
      _channel.invokeMethod<void>('publish', {
        'source': file.path,
        'destination': destination,
        'replaceExisting': replaceExisting,
      });

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
