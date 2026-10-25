// The browser version saves every file as a download; desktop builds never
// call this (they save through the native dialogs).
export 'browser_download_native.dart'
    if (dart.library.js_interop) 'browser_download_web.dart';
