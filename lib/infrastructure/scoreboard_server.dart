// Serving the scoreboard needs dart:io sockets; the browser build cannot
// listen for connections, so it has no scoreboard to offer.
export 'scoreboard_server_native.dart'
    if (dart.library.js_interop) 'scoreboard_server_web.dart';
