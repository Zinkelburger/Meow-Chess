import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
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

/// Opens an event to look at it without owning it. SQLite treats the file as
/// unchanging: it takes no locks, creates no recovery files beside it and
/// writes nothing, so reading a file can never alter or create one.
CommonDatabase openEventForReading(String path) {
  final uri = Uri.file(p.absolute(path));
  // SQLite accepts no host in a file: URI, so a share is `file:////host/…`.
  final name = uri.host.isEmpty
      ? uri.toString()
      : 'file:////${uri.host}${uri.path}';
  return native.sqlite3.open(
    '$name?mode=ro&immutable=1',
    mode: OpenMode.readOnly,
    uri: true,
  );
}

/// What tells the file now at [path] apart from any other: its device and
/// inode on Linux and macOS, so a different file that later takes the same
/// name is noticed. Null when nothing is there, or it cannot be reached.
/// Windows refuses to move, rename or delete a file SQLite has open, so
/// there being present is enough.
String? eventFileIdentity(String path) {
  if (Platform.isWindows || _stat == null) {
    return File(path).existsSync() ? 'present' : null;
  }
  return using((arena) {
    // Far larger than struct stat on any supported platform (144 bytes).
    final buffer = arena<Uint8>(512);
    final name = path.toNativeUtf8(allocator: arena);
    if (_stat!(name, buffer) != 0) return null;
    final fields = ByteData.sublistView(buffer.asTypedList(16));
    // st_dev then st_ino: two 64-bit fields on 64-bit Linux; on macOS a
    // 32-bit device, the mode and link count, then the 64-bit inode.
    final device = Platform.isMacOS
        ? fields.getInt32(0, Endian.host)
        : fields.getUint64(0, Endian.host);
    return '$device:${fields.getUint64(8, Endian.host)}';
  });
}

/// stat(2), or null where the C library does not export it under a name
/// known here; identity then falls back to the file being present.
final int Function(Pointer<Utf8>, Pointer<Uint8>)? _stat = () {
  if (!Platform.isLinux && !Platform.isMacOS) return null;
  // Intel macOS keeps the 64-bit-inode layout under its own symbol.
  for (final symbol in [if (Platform.isMacOS) r'stat$INODE64', 'stat']) {
    try {
      return DynamicLibrary.process().lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
        int Function(Pointer<Utf8>, Pointer<Uint8>)
      >(symbol);
    } on ArgumentError {
      // glibc before 2.33 has no stat symbol.
    }
  }
  return null;
}();

/// Whether the folder holding [path] can still be reached: false when a USB
/// stick or network share has gone, true when only the file itself has.
bool eventFolderReachable(String path) {
  try {
    return Directory(p.dirname(path)).existsSync();
  } on FileSystemException {
    return false;
  }
}

/// Nothing to do: SQLite's own sync has already put each commit on disk.
void eventStorageChanged() {}

/// History snapshots are stored zlib-compressed.
List<int> zlibEncode(List<int> bytes) => zlib.encode(bytes);

List<int> zlibDecode(List<int> bytes) => zlib.decode(bytes);
