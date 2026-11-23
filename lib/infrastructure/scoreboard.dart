import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/model.dart';
import '../domain/scoreboard.dart';
import 'scoreboard_page.dart';
import 'scoreboard_server.dart';

export '../domain/scoreboard.dart' show ScoreboardSettings;
export 'scoreboard_server.dart' show openInBrowser;

/// The scoreboard of the open event: what it shows, whether it is being
/// served, and where. It follows [source] (the event's controller), so a
/// posted round or a result reaches every screen at its next poll; a round
/// still under review is not in the event and never appears.
class Scoreboard extends ChangeNotifier {
  Scoreboard({
    required this.source,
    required this.event,
    ScoreboardSettings settings = const ScoreboardSettings(),
    DateTime Function() now = DateTime.now,
    BoardServer? server,
  }) : _settings = settings,
       _now = now {
    _server =
        server ?? BoardServer(page: () => scoreboardPage, board: () => board);
    source.addListener(_refresh);
    _refresh();
  }

  /// Whether this build can serve a scoreboard at all.
  static const supported = BoardServer.supported;

  final Listenable source;

  /// The event to show, or null once it has closed.
  final Event? Function() event;
  final DateTime Function() _now;
  late final BoardServer _server;
  ScoreboardSettings _settings;
  String _tables = '[]', _name = '';
  DateTime? _changed;
  List<String> _hosts = const [];
  bool _disposed = false;

  ScoreboardSettings get settings => _settings;
  set settings(ScoreboardSettings value) {
    _settings = value;
    _refresh();
    if (!_disposed) notifyListeners();
  }

  bool get running => _server.port != null;

  /// Whether other devices on the network can open the board.
  bool get network => _server.network;

  /// Why the last start failed, in the director's words, or null.
  String? problem;

  /// When what the board shows last changed: a round posted, a result in.
  DateTime? get changed => _changed;

  /// The address on this computer, or null while stopped.
  Uri? get localAddress => switch (_server.port) {
    final port? => Uri(
      scheme: 'http',
      host: 'localhost',
      port: port,
      path: '/',
    ),
    null => null,
  };

  /// The addresses a TV or a phone on the same network can open. Empty
  /// while stopped, while serving this computer only, or with no network.
  List<Uri> get networkAddresses => [
    if (_server.port case final port? when network)
      for (final host in _hosts)
        Uri(scheme: 'http', host: host, port: port, path: '/'),
  ];

  /// What the page polls: the event's name, the screen time, when the
  /// board last changed and its tables.
  String get board =>
      '{"event":${jsonEncode(_name)},"seconds":${_settings.seconds},'
      '"changed":${jsonEncode(_changed?.toIso8601String() ?? '')},'
      '"tables":$_tables}';

  void _refresh() {
    final e = event();
    if (e == null) return;
    final tables = jsonEncode([
      for (final t in scoreboardTables(e, _settings)) t.toJson(),
    ]);
    final same = tables == _tables && e.name == _name;
    if (tables != _tables || _changed == null) _changed = _now();
    _tables = tables;
    _name = e.name;
    // The panel shows the sections and the time of the last change.
    if (!same && !_disposed) notifyListeners();
  }

  /// Starts serving, or restarts on the other audience. [network] opens the
  /// board to the local network; otherwise only this computer can see it.
  Future<void> start({required bool network}) async {
    problem = null;
    try {
      await _server.start(network: network);
      _hosts = network ? await _server.hosts() : const [];
    } catch (error) {
      await _server.stop();
      problem =
          'The scoreboard could not start on this computer. Another program '
          'may be using the network, or a firewall refused it.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    await _server.stop();
    _hosts = const [];
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    source.removeListener(_refresh);
    _server.stop();
    super.dispose();
  }
}
