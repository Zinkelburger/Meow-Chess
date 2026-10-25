import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

/// The browser's SQLite: sqlite3.wasm (served beside the app) over a file
/// system kept in IndexedDB, so events survive closing the tab. Loaded once
/// by [initializeWebStorage] before the app starts.
late final WasmSqlite3 _sqlite3;
late final IndexedDbFileSystem _files;

CommonSqlite3 get sqlite3 => _sqlite3;

Future<void> initializeWebStorage() async {
  _sqlite3 = await WasmSqlite3.loadFromUrl(Uri.base.resolve('sqlite3.wasm'));
  _files = await IndexedDbFileSystem.open(dbName: 'meow-chess');
  _sqlite3.registerVirtualFileSystem(_files, makeDefault: true);
  // Ask the browser not to evict the events under storage pressure. It may
  // refuse; events are still kept, only without that promise.
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (_) {}
}

/// Waits until every change so far is written to IndexedDB.
Future<void> flushWebStorage() => _files.flush();

bool eventFileExists(String path) => _files.xAccess(path, 0) != 0;

/// Removes a stored file; a missing file is not an error.
void deleteEventFile(String path) {
  if (eventFileExists(path)) _files.xDelete(path, 0);
}

/// Stored names are already canonical: there are no links in IndexedDB.
String? resolveEventPath(String path) => eventFileExists(path) ? path : null;

bool sameEventFile(String a, String b) => a == b;

/// A name for a short-lived copy, such as a snapshot being downloaded.
String scratchEventPath() =>
    '/scratch/${DateTime.now().microsecondsSinceEpoch}.meow';

/// The bytes of a stored file, or null when there is none.
Uint8List? readEventFile(String path) {
  if (!eventFileExists(path)) return null;
  final file = _files
      .xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY)
      .file;
  try {
    final bytes = Uint8List(file.xFileSize());
    if (bytes.isNotEmpty) file.xRead(bytes, 0);
    return bytes;
  } finally {
    file.xClose();
  }
}

/// Replaces a stored file's contents with [bytes].
void writeEventFile(String path, List<int> bytes) {
  final file = _files
      .xOpen(
        Sqlite3Filename(path),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      )
      .file;
  try {
    file.xTruncate(0);
    file.xWrite(bytes is Uint8List ? bytes : Uint8List.fromList(bytes), 0);
  } finally {
    file.xClose();
  }
}

/// History snapshots are stored zlib-compressed, as on desktop; the browser
/// has no dart:io zlib.
List<int> zlibEncode(List<int> bytes) => const ZLibEncoder().encodeBytes(bytes);

List<int> zlibDecode(List<int> bytes) => const ZLibDecoder().decodeBytes(bytes);
