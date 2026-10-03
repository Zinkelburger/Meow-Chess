import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';

import 'rating_contract_test.dart'
    show doubleBlitz, exportFixture, readDbf, today;

void saveFixture(String name, Event event) {
  if (Platform.environment['MEOW_EXPORT_FIXTURES'] != '1') return;
  final directory = Directory('artifacts/dbf-importer/$name')
    ..createSync(recursive: true);
  for (final file in ratingPackage(event, today: today).entries) {
    File('${directory.path}/${file.key}').writeAsBytesSync(file.value);
  }
  File(
    '${directory.path}/expected-event.json',
  ).writeAsStringSync(event.encode());
}

void main() {
  for (final reverse in [false, true]) {
    test('mixed rounds use maximum schema, short section first: $reverse', () {
      final base = exportFixture();
      final sections = [
        base.sections.first,
        base.sections.last.copy(
          plannedRounds: 1,
          rounds: base.sections.last.rounds.take(1).toList(),
          timeControl: 'G/15',
        ),
      ];
      final event = base.copy(
        sections: reverse ? sections.reversed.toList() : sections,
      );
      validateEvent(event);
      expect(ratingPreflight(event, today: today), isEmpty);
      final files = ratingPackage(event, today: today);
      final rows = readDbf(files['TSEXPORT.DBF']!).$2;
      expect(
        rows.map((r) => r['S_TOT_RNDS']),
        reverse ? ['1', '12'] : ['12', '1'],
      );
      final (fields, details) = readDbf(files['TDEXPORT.DBF']!);
      expect(fields.last.$1, 'D_RND12');
      for (final row in details.where(
        (r) => r['D_SEC_NUM'] == (reverse ? '1' : '2'),
      )) {
        for (var n = 2; n <= 12; n++) {
          expect(row['D_RND${n.toString().padLeft(2, '0')}'], 'U0');
        }
      }
      saveFixture(reverse ? 'mixed-short-first' : 'mixed-long-first', event);
    });
  }

  for (final count in [1, 32]) {
    test('$count chronological rounds fit one detail record per player', () {
      final base = exportFixture();
      final players = base.players.take(2).toList();
      final event = base.copy(
        name: 'E' * 35,
        city: 'C' * 21,
        timeControl: 'G/90',
        players: [
          players.first.copy(reportName: 'N' * 30),
          players.last,
        ],
        sections: [
          Section(
            id: 's0',
            name: 'S' * 30,
            players: players.map((p) => p.id).toList(),
            plannedRounds: count,
            rounds: [
              for (var n = 1; n <= count; n++)
                Round(
                  number: n,
                  games: [
                    Game(
                      id: 'g$n',
                      white: players.first.id,
                      black: players.last.id,
                      board: 1,
                      outcome: Outcome.draw,
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      validateEvent(event);
      final (fields, rows) = readDbf(ratingPackage(event)['TDEXPORT.DBF']!);
      expect(fields, hasLength(7 + count));
      expect(rows, hasLength(2));
      saveFixture('rounds-$count', event);
    });
  }

  test('quad is a round robin with three chronological columns', () {
    final base = exportFixture();
    final players = base.players.take(4).toList();
    final ids = players.map((p) => p.id).toList();
    final event = base.copy(
      players: players,
      sections: [
        Section(
          id: 'quad',
          name: 'Quad',
          format: Format.quad,
          players: ids,
          plannedRounds: 3,
          rounds: [
            for (final (index, pairs) in roundRobinSchedule(ids).indexed)
              Round(
                number: index + 1,
                games: [
                  for (final (board, pair) in pairs.indexed)
                    Game(
                      id: '$index-$board',
                      white: pair.$1!,
                      black: pair.$2!,
                      board: board + 1,
                      outcome: Outcome.whiteWin,
                    ),
                ],
              ),
          ],
        ),
      ],
    );
    validateEvent(event);
    saveFixture('quad', event);
    final rows = readDbf(ratingPackage(event)['TSEXPORT.DBF']!).$2;
    expect(rows.single['S_TRN_TYPE'], 'R');
    expect(rows.single['S_TOT_RNDS'], '3');
  });

  test('same members can have independent one-round side-game entries', () {
    final base = exportFixture();
    final originals = base.players.take(2).toList();
    final extra = [
      for (final player in originals)
        Player(
          id: 'side-${player.id}',
          personId: player.id,
          name: player.name,
          memberId: player.memberId,
          rating: player.rating,
          state: player.state,
        ),
    ];
    final event = base.copy(
      players: [...base.players, ...extra],
      sections: [
        ...base.sections,
        Section(
          id: 'side',
          name: 'Side games',
          players: extra.map((p) => p.id).toList(),
          plannedRounds: 1,
          rounds: [
            Round(
              number: 1,
              games: [
                Game(
                  id: 'side-game',
                  white: extra.first.id,
                  black: extra.last.id,
                  board: 20,
                  outcome: Outcome.whiteWin,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    validateEvent(event);
    expect(ratingPreflight(event), isEmpty);
    saveFixture('side-games', event);
  });

  test(
    'four-digit opponent numbers survive fixed seven-byte result fields',
    () {
      final base = exportFixture();
      final players = [
        for (var n = 1; n <= 1000; n++)
          Player(
            id: 'large-$n',
            name: 'Given$n Family$n',
            memberId: '${91000000 + n}',
            rating: n == 1000 ? 4000 : 0,
            state: 'MA',
          ),
      ];
      final event = base.copy(
        players: players,
        sections: [
          Section(
            id: 'large',
            name: 'Four digit opponents',
            players: players.map((p) => p.id).toList(),
            plannedRounds: 1,
            rounds: [
              Round(
                number: 1,
                games: [
                  for (var n = 0; n < 500; n++)
                    Game(
                      id: 'large-game-$n',
                      white: players[n].id,
                      black: players[999 - n].id,
                      board: n + 1,
                      outcome: Outcome.whiteWin,
                    ),
                ],
              ),
            ],
          ),
        ],
      );
      validateEvent(event);
      final rows = readDbf(ratingPackage(event)['TDEXPORT.DBF']!).$2;
      expect(rows.first['D_RND01'], 'W1000W');
      expect(rows.last['D_RND01'], 'L1B');
      saveFixture('four-digit-opponents', event);
    },
  );

  test('double-game blitz and assistant TDs survive an independent reader', () {
    final event = doubleBlitz();
    expect(ratingPreflight(event, today: today), isEmpty);
    saveFixture('double-blitz', event);
    final stateless = event.copy(
      players: [
        for (final p in event.players) p.id == 'p2' ? p.copy(state: '') : p,
      ],
    );
    expect(ratingPreflight(stateless, today: today), isEmpty);
    saveFixture('blank-state', stateless);
  });
}
