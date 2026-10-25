import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../application/diagnostics.dart';

/// For tests: behave as if the filesystem has no exclusive rename, as on
/// NFS, exFAT, SMB or under the macOS App Sandbox.
bool debugExclusiveRenameUnsupported = false;

/// For tests: the directory sync that follows a successful publication.
void Function(String path) debugSyncPublishedDirectory = syncDirectory;

/// Atomically publishes a complete file or directory, exclusively by default.
/// Fail closed on unsupported filesystems: ordinary rename can destroy a backup.
void publishFile(
  String source,
  String destination, {
  bool replaceExisting = false,
}) {
  if (source.contains('\u0000') || destination.contains('\u0000')) {
    throw ArgumentError('File paths cannot contain NUL.');
  }
  using((arena) {
    int error;
    if (Platform.isWindows) {
      final library = DynamicLibrary.open('kernel32.dll');
      final move = library
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
            int Function(Pointer<Utf16>, Pointer<Utf16>, int)
          >('MoveFileExW');
      final getError = library
          .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
      // MOVEFILE_WRITE_THROUGH, with replacement only after user confirmation.
      if (move(
            windowsExtendedPath(source).toNativeUtf16(allocator: arena),
            windowsExtendedPath(destination).toNativeUtf16(allocator: arena),
            replaceExisting ? 9 : 8,
          ) !=
          0) {
        return;
      }
      error = getError();
    } else if (Platform.isLinux || Platform.isMacOS) {
      final library = DynamicLibrary.process();
      final from = source.toNativeUtf8(allocator: arena);
      final to = destination.toNativeUtf8(allocator: arena);
      final errno = library
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            Platform.isLinux ? '__errno_location' : '__error',
          )();
      int path2(String name) =>
          library.lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
            int Function(Pointer<Utf8>, Pointer<Utf8>)
          >(name)(from, to);
      if (replaceExisting) {
        error = path2('rename') == 0 ? 0 : errno.value;
      } else {
        error = _renameExclusively(library, from, to, errno);
        if (error != 0 && _exclusiveRenameUnsupported(error)) {
          if (FileSystemEntity.typeSync(source, followLinks: false) !=
              FileSystemEntityType.file) {
            throw FileSystemException(
              'This drive cannot save a folder without risking another one of the same name. Choose a destination on another drive',
              destination,
              OSError('Exclusive rename is unsupported', error),
            );
          }
          // link() refuses an existing name just as an exclusive rename does,
          // through calls the App Sandbox and most filesystems allow.
          error = path2('link') == 0 ? 0 : errno.value;
          if (error == 0) {
            final unlink = library
                .lookupFunction<
                  Int32 Function(Pointer<Utf8>),
                  int Function(Pointer<Utf8>)
                >('unlink');
            if (unlink(from) != 0) {
              // The complete file is already published; callers remove their
              // staging names, so a leftover second name is harmless.
              Diagnostics.record(
                'publish file',
                'staging name left behind',
                error: OSError('unlink failed', errno.value),
                context: {'path': source},
              );
            }
          } else if (Platform.isLinux
              ? const {1, 38, 95}.contains(error)
              : const {1, 45, 78, 102}.contains(error)) {
            // EPERM, ENOSYS, ENOTSUP/EOPNOTSUPP: no hard links either (FAT,
            // exFAT, some network shares). EEXIST stays an ordinary failure.
            throw FileSystemException(
              'This drive cannot save a file without risking another one of the same name. Choose a destination on another drive',
              destination,
              OSError('Exclusive publication is unsupported', error),
            );
          }
        }
      }
      if (error == 0) {
        _syncPublished(p.dirname(destination));
        if (!p.equals(
          p.absolute(p.dirname(source)),
          p.absolute(p.dirname(destination)),
        )) {
          _syncPublished(p.dirname(source));
        }
        return;
      }
    } else {
      throw UnsupportedError('Exclusive file publication is unavailable.');
    }
    throw FileSystemException(
      'Could not publish the complete file',
      destination,
      OSError('Atomic rename failed', error),
    );
  });
}

/// renameat2(RENAME_NOREPLACE) on Linux, renamex_np(RENAME_EXCL) on macOS;
/// returns 0 or the errno, ENOSYS when the C library lacks the call.
int _renameExclusively(
  DynamicLibrary library,
  Pointer<Utf8> from,
  Pointer<Utf8> to,
  Pointer<Int32> errno,
) {
  if (debugExclusiveRenameUnsupported) return Platform.isLinux ? 22 : 1;
  try {
    if (Platform.isLinux) {
      final rename = library
          .lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Uint32),
            int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
          >('renameat2');
      return rename(-100, from, -100, to, 1) == 0 ? 0 : errno.value;
    }
    final rename = library
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, Pointer<Utf8>, int)
        >('renamex_np');
    return rename(from, to, 4) == 0 ? 0 : errno.value; // RENAME_EXCL
  } on ArgumentError {
    // glibc before 2.28 has no renameat2 wrapper.
    return Platform.isLinux ? 38 : 78;
  }
}

/// Errors meaning the filesystem or sandbox lacks an exclusive rename, as
/// opposed to the destination existing: Linux EINVAL, ENOSYS, EOPNOTSUPP;
/// macOS EPERM (App Sandbox), EINVAL, ENOTSUP, ENOSYS, EOPNOTSUPP.
bool _exclusiveRenameUnsupported(int error) => Platform.isLinux
    ? const {22, 38, 95}.contains(error)
    : const {1, 22, 45, 78, 102}.contains(error);

/// The file is already published under its final name; a directory sync that
/// fails afterwards only weakens durability, so it is logged, not reported
/// as a failed save.
void _syncPublished(String directory) {
  try {
    debugSyncPublishedDirectory(directory);
  } on FileSystemException catch (error) {
    Diagnostics.record(
      'publish file',
      'directory sync failed',
      error: error,
      context: {'directory': directory},
    );
  }
}

/// MoveFileExW refuses paths of MAX_PATH (260) or more without the `\\?\`
/// prefix, which also turns off normalization, so the path is normalized first.
String windowsExtendedPath(String path) {
  if (path.startsWith(r'\\?\')) return path;
  final full = p.windows.normalize(
    p.windows.isAbsolute(path) ? path : p.join(Directory.current.path, path),
  );
  if (full.length < 260) return path;
  if (RegExp(r'^[A-Za-z]:\\').hasMatch(full)) return '\\\\?\\$full';
  if (RegExp(r'^\\\\[^\\]').hasMatch(full)) {
    return '\\\\?\\UNC\\${full.substring(2)}';
  }
  return path;
}

/// Publishes a flat package whose component files have already been flushed.
/// Persisting file contents alone does not persist their names in the package;
/// sync those entries before making the complete package visible to its caller.
void publishDirectory(String source, String destination) {
  syncDirectory(source);
  publishFile(source, destination);
}

/// Persists directory entries on POSIX, separately from the file's contents.
/// Windows publication uses MOVEFILE_WRITE_THROUGH instead.
void syncDirectory(String path) {
  if (Platform.isWindows) return;
  if (!Platform.isLinux && !Platform.isMacOS) {
    throw UnsupportedError('Directory synchronization is unavailable.');
  }
  if (path.contains('\u0000')) throw ArgumentError('Invalid directory path.');
  using((arena) {
    final library = DynamicLibrary.process();
    final open = library
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)
        >('open');
    final sync = library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
    final close = library
        .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
    final errno = library
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
          Platform.isLinux ? '__errno_location' : '__error',
        )();
    // O_RDONLY | O_DIRECTORY: never accidentally sync a regular file.
    final descriptor = open(
      path.toNativeUtf8(allocator: arena),
      Platform.isLinux ? 0x10000 : 0x100000,
    );
    if (descriptor < 0) {
      throw FileSystemException(
        'Could not open directory for synchronization',
        path,
        OSError('open failed', errno.value),
      );
    }
    try {
      int result;
      do {
        result = sync(descriptor);
      } while (result != 0 && errno.value == 4); // EINTR
      if (result != 0) {
        throw FileSystemException(
          'Could not persist the published file name',
          path,
          OSError('fsync failed', errno.value),
        );
      }
    } finally {
      close(descriptor);
    }
  });
}

/// Creates parents and persists each newly created directory entry. The final
/// directory is synced again by [publishFile] after its file is published.
void createDirectoryDurably(String path) {
  final missing = <String>[];
  var current = p.absolute(path);
  while (!Directory(current).existsSync()) {
    missing.add(current);
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
  Directory(path).createSync(recursive: true);
  for (final directory in missing) {
    syncDirectory(p.dirname(directory));
  }
}
