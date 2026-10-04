import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/model.dart';
import 'publish_file.dart';
import 'sqlite_event_repository.dart';

/// Saves a report to a destination accepted by the native replacement dialog.
/// Tournament databases and their recovery files are never report destinations.
void writeArtifact(String destination, List<int> bytes) {
  if (!p.isAbsolute(destination)) {
    throw const TournamentException('Choose a full path for the report.');
  }
  void checkDestination() {
    const protected = TournamentException(
      'This is a tournament database or recovery file. Choose another filename for the report.',
    );
    final name = p.basename(destination).toLowerCase();
    if (SqliteEventRepository.ownsPath(destination) ||
        name.endsWith('.meow') ||
        ['-wal', '-shm', '-journal'].any(name.endsWith)) {
      throw protected;
    }
    final type = FileSystemEntity.typeSync(destination, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw const TournamentException(
        'Choose a regular file rather than a symbolic link for the report.',
      );
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const TournamentException('Choose a file for the report.');
    }
    if (['-wal', '-shm', '-journal'].any(
      (suffix) =>
          FileSystemEntity.typeSync(
            '$destination$suffix',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound,
    )) {
      throw protected;
    }
    if (type == FileSystemEntityType.file) {
      final file = File(destination).openSync();
      try {
        final header = file.readSync(16);
        // Headers protect renamed databases and hard links too.
        final database =
            String.fromCharCodes(header) == 'SQLite format 3\u0000';
        final wal =
            header.length >= 4 &&
            header[0] == 0x37 &&
            header[1] == 0x7f &&
            header[2] == 0x06 &&
            (header[3] == 0x82 || header[3] == 0x83);
        if (database || wal) throw protected;
      } finally {
        file.closeSync();
      }
    }
  }

  checkDestination();
  // Native Save dialogs select an existing directory. Do not create a tree
  // whose durability would need to be established separately.
  final staging = Directory(
    p.dirname(destination),
  ).createTempSync('.meow-report-');
  try {
    final file = File(p.join(staging.path, 'complete'));
    file.writeAsBytesSync(bytes, flush: true);
    checkDestination();
    publishFile(file.path, destination, replaceExisting: true);
  } finally {
    staging.deleteSync(recursive: true);
  }
}
