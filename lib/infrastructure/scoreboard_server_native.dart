import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The scoreboard's web server: two read-only addresses, the page and the
/// board it polls. It listens on this computer only unless [network] is
/// asked for, and then on the local network, for a TV or phones on the same
/// Wi-Fi. It never reads anything a browser sends beyond the path.
class BoardServer {
  BoardServer({required this.page, required this.board});
  static const supported = true;

  /// The port tried first, so an address written on a whiteboard still
  /// works after a restart. Any free port is used when it is taken.
  static const preferredPort = 8086;

  /// The page's HTML and the board's JSON, read on every request.
  final String Function() page, board;
  HttpServer? _server;
  bool _network = false;

  int? get port => _server?.port;
  bool get network => _network;

  Future<void> start({required bool network}) async {
    await stop();
    final address = network
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    HttpServer server;
    try {
      server = await HttpServer.bind(address, preferredPort);
    } on SocketException {
      server = await HttpServer.bind(address, 0);
    }
    _server = server;
    _network = network;
    server.listen(_answer, onError: (Object _) {});
  }

  void _answer(HttpRequest request) {
    final response = request.response;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'unsafe-inline'; "
            "style-src 'unsafe-inline'; connect-src 'self'; "
            "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      );
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      } else {
        switch (request.uri.path) {
          case '/' || '/index.html':
            response.headers.contentType = ContentType.html;
            if (request.method == 'GET') response.add(utf8.encode(page()));
          case '/board.json':
            response.headers.contentType = ContentType.json;
            if (request.method == 'GET') response.add(utf8.encode(board()));
          default:
            response.statusCode = HttpStatus.notFound;
        }
      }
    } finally {
      // A browser that went away mid-reply is not an error worth keeping.
      unawaited(response.close().catchError((Object _) {}));
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// This computer's addresses on its networks, for a TV or a phone to
  /// reach: `192.168.1.20`. Empty when it is on none.
  Future<List<String>> hosts() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
      ];
    } on SocketException {
      return const [];
    }
  }
}

/// Opens [address] in the computer's browser. False when it could not, so
/// the caller can say to copy the address instead.
Future<bool> openInBrowser(Uri address) async {
  final url = address.toString();
  final (command, arguments) = Platform.isWindows
      ? ('rundll32', ['url.dll,FileProtocolHandler', url])
      : Platform.isMacOS
      ? ('open', [url])
      : ('xdg-open', [url]);
  try {
    final result = await Process.run(
      command,
      arguments,
    ).timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  } on TimeoutException {
    // Some openers stay alive as long as the browser they started.
    return true;
  }
}
