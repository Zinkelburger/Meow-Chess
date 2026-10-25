// BBP Pairings is compiled native code (hook/build.dart); the browser build
// has no FIDE Dutch engine yet.
export 'bbp_pairings_native.dart'
    if (dart.library.js_interop) 'bbp_pairings_web.dart';
