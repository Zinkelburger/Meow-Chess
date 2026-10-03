import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Atomically publishes a complete sibling file, exclusively by default.
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
            source.toNativeUtf16(allocator: arena),
            destination.toNativeUtf16(allocator: arena),
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
      final int result;
      if (Platform.isLinux) {
        final rename = library
            .lookupFunction<
              Int32 Function(
                Int32,
                Pointer<Utf8>,
                Int32,
                Pointer<Utf8>,
                Uint32,
              ),
              int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
            >('renameat2');
        result = rename(-100, from, -100, to, replaceExisting ? 0 : 1);
      } else {
        final rename = library
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32),
              int Function(Pointer<Utf8>, Pointer<Utf8>, int)
            >('renamex_np');
        result = rename(from, to, replaceExisting ? 0 : 4); // RENAME_EXCL
      }
      if (result == 0) return;
      error = errno.value;
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
