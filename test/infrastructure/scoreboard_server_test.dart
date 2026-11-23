import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/scoreboard.dart';

Event event({
  Outcome outcome = Outcome.unreported,
  String name = 'Fall Open',
}) => Event(
  id: 'e',
  name: name,
  date: '2026-11-21',
  players: [
    Player(id: 'a', name: 'Ann <b>', memberId: '12345678', notes: 'private'),
    Player(id: 'b', name: 'Bob'),
  ],
  sections: [
    Section(
      id: 's',
      name: 'Open',
      players: const ['a', 'b'],
      rounds: [
        Round(
          number: 1,
          games: [
            Game(id: 'g', white: 'a', black: 'b', board: 1, outcome: outcome),
          ],
        ),
      ],
    ),
  ],
);

Future<(int, String, HttpHeaders)> get(
  Uri address, {
  String method = 'GET',
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, address);
    final response = await request.close();
    return (
      response.statusCode,
      await utf8.decodeStream(response),
      response.headers,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'serves the page and the board, read-only, and follows the event',
    () async {
      final source = ChangeNotifier();
      var current = event();
      var clock = DateTime(2026, 11, 21, 10);
      final board = Scoreboard(
        source: source,
        event: () => current,
        now: () => clock,
      );
      addTearDown(board.dispose);
      expect(board.running, isFalse);
      expect(board.localAddress, isNull);

      await board.start(network: false);
      expect(board.problem, isNull);
      expect(board.running, isTrue);
      expect(board.network, isFalse);
      expect(board.networkAddresses, isEmpty);
      final home = board.localAddress!;
      expect(home.host, 'localhost');

      final (status, page, headers) = await get(home);
      expect(status, 200);
      expect(headers.contentType!.mimeType, 'text/html');
      expect(headers.value('cache-control'), 'no-store');
      expect(
        headers.value('content-security-policy'),
        contains("default-src 'none'"),
      );
      expect(page, contains('<title>Scoreboard</title>'));
      // Names reach the page as text, never as markup.
      expect(page, isNot(contains('innerHTML')));

      final (_, body, jsonHeaders) = await get(home.resolve('board.json'));
      expect(jsonHeaders.contentType!.mimeType, 'application/json');
      final first = jsonDecode(body) as Map<String, dynamic>;
      expect(first['event'], 'Fall Open');
      expect(first['seconds'], 10);
      expect(first['changed'], '2026-11-21T10:00:00.000');
      final table = (first['tables'] as List).single as Map<String, dynamic>;
      expect(table['rows'], [
        ['1', 'Ann <b>', '', 'Bob'],
      ]);
      expect(body, isNot(contains('12345678')));
      expect(body, isNot(contains('private')));

      // Nothing but the two addresses, and nothing but reading.
      expect((await get(home.resolve('event.meow'))).$1, 404);
      expect((await get(home.resolve('board.json'), method: 'POST')).$1, 405);

      // A result changes the board and the time of its last change.
      clock = DateTime(2026, 11, 21, 10, 30);
      current = event(outcome: Outcome.blackWin);
      source.notifyListeners();
      final second =
          jsonDecode((await get(home.resolve('board.json'))).$2)
              as Map<String, dynamic>;
      expect(((second['tables'] as List).first as Map)['rows'], [
        ['1', 'Ann <b>', '0–1', 'Bob'],
      ]);
      expect(second['changed'], '2026-11-21T10:30:00.000');

      // A change the board does not show leaves that time alone.
      clock = DateTime(2026, 11, 21, 11);
      board.settings = board.settings.copy(seconds: 20);
      final third =
          jsonDecode((await get(home.resolve('board.json'))).$2)
              as Map<String, dynamic>;
      expect(third['seconds'], 20);
      expect(third['changed'], '2026-11-21T10:30:00.000');

      await board.stop();
      expect(board.running, isFalse);
      await expectLater(get(home), throwsA(isA<SocketException>()));
    },
  );

  test(
    'shared with the network, it lists this computer\'s addresses',
    () async {
      final board = Scoreboard(source: ChangeNotifier(), event: event);
      addTearDown(board.dispose);
      await board.start(network: true);
      expect(board.problem, isNull);
      expect(board.network, isTrue);
      for (final address in board.networkAddresses) {
        expect(address.scheme, 'http');
        expect(address.port, board.localAddress!.port);
        expect(address.host, isNot('127.0.0.1'));
      }
      // This computer still reaches it.
      expect(
        (await get(board.localAddress!.replace(host: '127.0.0.1'))).$1,
        200,
      );
    },
  );
}
