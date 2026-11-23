import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/scoreboard.dart';
import 'package:meow_chess/infrastructure/scoreboard_server.dart';
import 'package:meow_chess/ui/scoreboard_panel.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

/// A server that listens nowhere: it only records what it was asked.
class FakeServer extends BoardServer {
  FakeServer() : super(page: () => '', board: () => '');
  int? _port;
  bool _network = false;
  bool fail = false;
  final starts = <bool>[];

  @override
  int? get port => _port;
  @override
  bool get network => _network;

  @override
  Future<void> start({required bool network}) async {
    if (fail) throw StateError('no socket');
    starts.add(network);
    _port = 8086;
    _network = network;
  }

  @override
  Future<void> stop() async => _port = null;

  @override
  Future<List<String>> hosts() async => const ['192.168.1.20'];
}

Future<void> mount(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: Align(alignment: Alignment.topRight, child: panel),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('starts for this computer, then shares with the network', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    final server = FakeServer();
    final board = Scoreboard(source: c, event: () => c.event, server: server);
    addTearDown(board.dispose);
    final opened = <Uri>[];
    var saves = 0;
    await mount(
      tester,
      ScoreboardPanel(
        scoreboard: board,
        event: () => c.event!,
        onSettings: () => saves++,
        open: (address) async {
          opened.add(address);
          return false;
        },
        onClose: () {},
      ),
    );
    String status() => tester
        .widget<Text>(find.byKey(const ValueKey('scoreboard-status')))
        .data!;
    expect(status(), 'Off');
    expect(find.text('http://localhost:8086/'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('scoreboard-start')));
    await tester.pumpAndSettle();
    expect(server.starts, [false]);
    expect(status(), 'On, for this computer only');
    expect(find.text('http://localhost:8086/'), findsOne);
    expect(find.text('http://192.168.1.20:8086/'), findsNothing);

    // No browser opened: the panel says to copy the address.
    await tester.tap(find.byKey(const ValueKey('scoreboard-open')));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'http://localhost:8086/');
    expect(find.textContaining('Copy the address'), findsOne);

    // Sharing a running board restarts it for the network, with a QR code.
    await tester.tap(find.byKey(const ValueKey('scoreboard-network')));
    await tester.pumpAndSettle();
    expect(server.starts, [false, true]);
    expect(status(), 'On, for this computer and its network');
    expect(find.text('http://192.168.1.20:8086/'), findsOne);
    expect(
      find.byKey(const ValueKey('scoreboard-qr-http://192.168.1.20:8086/')),
      findsOne,
    );

    // What it shows applies at once and is handed back to be saved.
    await tester.tap(find.byKey(const ValueKey('scoreboard-standings')));
    await tester.pump();
    expect(board.settings.standings, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('scoreboard-seconds')),
      '25',
    );
    await tester.pump();
    expect(board.settings.seconds, 25);
    // Out of range is not applied.
    await tester.enterText(
      find.byKey(const ValueKey('scoreboard-seconds')),
      '2',
    );
    await tester.pump();
    expect(board.settings.seconds, 25);
    final second = c.event!.sections[1];
    await tester.tap(find.byKey(ValueKey('scoreboard-section-${second.id}')));
    await tester.pump();
    expect(board.settings.hidden, {second.id});
    expect(saves, 3);
    await tester.tap(find.byKey(const ValueKey('scoreboard-pairings')));
    await tester.pump();
    expect(find.textContaining('the board is blank'), findsOne);

    await tester.tap(find.byKey(const ValueKey('scoreboard-stop')));
    await tester.pumpAndSettle();
    expect(status(), 'Off');
    expect(find.text('http://localhost:8086/'), findsNothing);
  });

  testWidgets('a start that fails says so and stays off', (tester) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final server = FakeServer()..fail = true;
    final board = Scoreboard(source: c, event: () => c.event, server: server);
    addTearDown(board.dispose);
    await mount(
      tester,
      ScoreboardPanel(scoreboard: board, event: () => c.event!, onClose: () {}),
    );
    await tester.tap(find.byKey(const ValueKey('scoreboard-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not start'), findsOne);
    expect(find.byKey(const ValueKey('scoreboard-start')), findsOne);
    // One section: there is no section list to choose from.
    expect(find.text('Sections'), findsNothing);
  });
}
