// Where event databases live: files on desktop, an IndexedDB-backed SQLite
// file system in the browser (see sqlite_platform_web.dart).
export 'sqlite_platform_native.dart'
    if (dart.library.js_interop) 'sqlite_platform_web.dart';
