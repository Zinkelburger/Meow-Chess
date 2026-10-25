import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as native;

CommonSqlite3 get sqlite3 => native.sqlite3;

bool eventFileExists(String path) => File(path).existsSync();

/// Removes a file SQLite created; a missing file is not an error.
void deleteEventFile(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
}

/// The file's canonical name with symlinks resolved, or null when it is gone.
String? resolveEventPath(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

/// Whether two existing names are the same file, such as through a hard link.
bool sameEventFile(String a, String b) {
  try {
    return FileSystemEntity.identicalSync(a, b);
  } on FileSystemException {
    // Journal creation/removal and external renames can race a stat.
    return false;
  }
}

/// A name for a short-lived copy, such as a snapshot being downloaded.
String scratchEventPath() => p.join(
  Directory.systemTemp.path,
  'meow-$pid-${DateTime.now().microsecondsSinceEpoch}.meow',
);

/// The bytes of a file, or null when there is none.
Uint8List? readEventFile(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsBytesSync() : null;
}

/// History snapshots are stored zlib-compressed.
List<int> zlibEncode(List<int> bytes) => zlib.encode(bytes);

List<int> zlibDecode(List<int> bytes) => zlib.decode(bytes);
