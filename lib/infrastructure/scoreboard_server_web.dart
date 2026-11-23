/// The browser build's scoreboard server: there is none. A web page cannot
/// listen for connections, so the Scoreboard button is left out there.
class BoardServer {
  BoardServer({required this.page, required this.board});
  static const supported = false;
  final String Function() page, board;
  int? get port => null;
  bool get network => false;

  Future<void> start({required bool network}) async =>
      throw UnsupportedError('The scoreboard needs the desktop app.');
  Future<void> stop() async {}
  Future<List<String>> hosts() async => const [];
}

/// Opens [address] in the computer's browser. False when it could not.
Future<bool> openInBrowser(Uri address) async => false;
