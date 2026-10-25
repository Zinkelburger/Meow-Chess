// Native file publication needs dart:ffi; the browser build keeps its events
// in IndexedDB and hands every other file to the browser as a download.
export 'publish_file_native.dart'
    if (dart.library.js_interop) 'publish_file_web.dart';
