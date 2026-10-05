import 'dart:io';

import 'package:flutter/foundation.dart';

import '../application/event_repository.dart';
import 'native_file_replacement.dart';
import 'sqlite_event_repository.dart';

/// Save-dialog destinations have replacement approval and a file access grant.
/// SQLite still owns snapshot creation, validation, and replacement protection.
Future<void> saveSelectedEvent(
  EventRepository repository,
  String destination,
) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) {
    repository.backup(destination, replaceExisting: true);
    return;
  }
  SqliteEventRepository.validateBackupDestination(destination);
  final replaceExisting = File(destination).existsSync();
  final staging = await NativeFileReplacement.prepare(destination);
  try {
    repository.backup(staging.file.path);
    await SqliteEventRepository.replaceBackup(
      destination,
      (replaceExisting) => staging.publish(replaceExisting: replaceExisting),
      replaceExisting: replaceExisting,
    );
  } finally {
    staging.dispose();
  }
}
