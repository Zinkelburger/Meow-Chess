import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';

import 'dbf_byte_contract_test.dart'
    show
        dbfCells,
        dbfRecords,
        detailSchema,
        expectDbfFraming,
        headerSchema,
        sectionSchema,
        syntheticEvent,
        syntheticPlayer;
import 'dbf_importer_test.dart' show saveFixture;
import '../dbf_reader.dart' show readDbf;
import 'rating_contract_test.dart' show today;

/// Byte-for-byte 2C records for tournament shapes the other contracts leave
/// out: withdrawals and last-round half-point byes, credited officials across
/// several sections, every text field at its exact width, four-digit pair
/// numbers and mixed rating kinds. Each package that is saved is also checked
/// by scripts/verify_dbf.py against its source event.

/// One TDEXPORT record: the fixed player columns, then one cell per round.
String _detail(
  int section,
  int pair,
  Player p,
  String name,
  List<String> cells,
) =>
    ' ${dbfCells([('', 12), ('$section', 2), ('$pair', 4), (p.memberId, 8), (name, 30), (p.state, 2), ('${p.rating}', 4), for (final c in cells) (c, 7)])}';

Game _game(String id, String white, String black, int board, Outcome o) =>
    Game(id: id, white: white, black: black, board: board, outcome: o);

/// Five players over three rounds. Player 4 withdraws after drawing round 1
/// and is carried as a zero-point "Withdrawn" bye, as pairing records it;
/// player 3 takes a requested half-point bye in the final round; players 5
/// and 2 receive the full-point pairing byes.
Event _withdrawal() {
  final players = [
    for (var i = 1; i <= 5; i++) syntheticPlayer(i, rating: 1600 - i * 20),
  ];
  return syntheticEvent(
    players: [
      for (final p in players) p.id == 'p4' ? p.copy(withdrawn: true) : p,
    ],
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: 3,
        rounds: [
          Round(
            number: 1,
            games: [
              _game('a', 'p1', 'p2', 1, Outcome.whiteWin),
              _game('b', 'p3', 'p4', 2, Outcome.draw),
            ],
            byes: const [ByeAward('p5', 2, 'Pairing bye', allocated: true)],
          ),
          Round(
            number: 2,
            games: [
              _game('c', 'p3', 'p1', 1, Outcome.blackWin),
              _game('d', 'p5', 'p2', 2, Outcome.whiteWin),
            ],
            byes: const [ByeAward('p4', 0, 'Withdrawn')],
          ),
          Round(
            number: 3,
            games: [_game('e', 'p5', 'p1', 1, Outcome.draw)],
            byes: const [
              ByeAward('p3', 1, 'Requested bye'),
              ByeAward('p2', 2, 'Pairing bye', allocated: true),
              ByeAward('p4', 0, 'Withdrawn'),
            ],
          ),
        ],
      ),
    ],
  );
}

/// [count] other TDs as a director might type them, with commas, semicolons
/// and spaces mixed; the report lists them comma-separated. 28 IDs and their
/// commas are 251 characters, the most H_OTHER_TD holds; 29 would need 260.
String _otherTds(int count) => [
  for (var i = 1; i <= count; i++)
    '${20000000 + i}${i == count ? '' : const [', ', ';', ' '][i % 3]}',
].join();

/// Two reported sections with an assistant chief TD and the most other TDs
/// that fit. The sections play different round counts, so the shorter one's
/// unused column is U0 padding.
Event _officials({bool withEmptySection = false}) {
  final players = [for (var i = 1; i <= 6; i++) syntheticPlayer(i)];
  return syntheticEvent(
    players: players,
    sections: [
      Section(
        id: 'open',
        name: 'Open',
        players: const ['p1', 'p2', 'p3', 'p4'],
        plannedRounds: 2,
        rounds: [
          Round(
            number: 1,
            games: [
              _game('o1', 'p1', 'p3', 1, Outcome.whiteWin),
              _game('o2', 'p4', 'p2', 2, Outcome.draw),
            ],
          ),
          Round(
            number: 2,
            games: [
              _game('o3', 'p2', 'p1', 1, Outcome.blackWin),
              _game('o4', 'p3', 'p4', 2, Outcome.whiteWin),
            ],
          ),
        ],
      ),
      // Sections with no entrants are not reported and take no number.
      if (withEmptySection)
        Section(id: 'empty', name: 'Novice', players: const []),
      Section(
        id: 'reserve',
        name: 'Reserve',
        players: const ['p5', 'p6'],
        plannedRounds: 1,
        boardStart: 3,
        rounds: [
          Round(
            number: 1,
            games: [_game('r1', 'p5', 'p6', 3, Outcome.blackWin)],
          ),
        ],
      ),
    ],
  ).copy(assistantTdId: '00123457', otherTdIds: _otherTds(28));
}

const _longEvent = 'Greater Boston Spring Chess Classic'; // 35
const _longCity = 'Manchester-by-the-Sea'; // 21
const _longSection = 'Under 1900 Reserve Section Two'; // 30
const _longName = 'Alexandrina Featherstonehaugh'; // reports as 30

/// Every free-text field at exactly its 2C width.
Event _widest() {
  final players = [
    syntheticPlayer(1).copy(name: _longName),
    syntheticPlayer(2),
  ];
  return syntheticEvent(
    players: players,
    sections: [
      Section(
        id: 's',
        name: _longSection,
        players: const ['p1', 'p2'],
        plannedRounds: 1,
        rounds: [
          Round(number: 1, games: [_game('g', 'p1', 'p2', 1, Outcome.draw)]),
        ],
      ),
    ],
  ).copy(name: _longEvent, city: _longCity);
}

/// Published, provisional, unrated and TD-assigned ratings side by side.
Event _ratingMix() {
  final players = [
    // An established rating at the 2C maximum fills D_RATING.
    syntheticPlayer(1, rating: 4000),
    // A provisional rating is still the published number.
    syntheticPlayer(2, rating: 850).copy(ratingNote: 'Provisional, 6 games'),
    // Unrated, with a rating assigned for pairing and prizes (rule 28).
    syntheticPlayer(3, rating: 0).copy(
      pairingRating: 1200,
      prizeRating: 1100,
      ratingNote: 'Assigned for pairing',
    ),
    // Unrated, with a disclosed foreign rating (rule 28C2).
    syntheticPlayer(
      4,
      rating: 0,
    ).copy(foreignRating: 2100, foreignFederation: 'FIDE'),
  ];
  return syntheticEvent(
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: 1,
        rounds: [
          Round(
            number: 1,
            games: [
              _game('a', 'p1', 'p3', 1, Outcome.whiteWin),
              _game('b', 'p4', 'p2', 2, Outcome.blackWin),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('a withdrawal reports U0 and a last-round half-point bye H0', () {
    final event = _withdrawal();
    validateEvent(event);
    expect(ratingPreflight(event, today: today), isEmpty);
    final files = ratingPackage(event, today: today);
    expectDbfFraming(
      files['TDEXPORT.DBF']!,
      fields: detailSchema(3),
      records: 5,
      date: DateTime(2024, 2, 28),
    );
    final p = {for (final p in event.players) p.id: p};
    expect(
      dbfRecords(files['TDEXPORT.DBF']!),
      [
        _detail(1, 1, p['p1']!, 'FAMILY1, GIVEN1', ['W2W', 'W3B', 'D5B']),
        _detail(1, 2, p['p2']!, 'FAMILY2, GIVEN2', ['L1B', 'L5B', 'B0']),
        _detail(1, 3, p['p3']!, 'FAMILY3, GIVEN3', ['D4W', 'L1W', 'H0']),
        // Withdrawn after round 1: still entrant 4, unplayed afterwards.
        _detail(1, 4, p['p4']!, 'FAMILY4, GIVEN4', ['D3B', 'U0', 'U0']),
        _detail(1, 5, p['p5']!, 'FAMILY5, GIVEN5', ['B0', 'W2W', 'D1W']),
      ].join(),
    );
    // A file without the zero-point "Withdrawn" records reads the same.
    final unrecorded = event.copy(
      sections: [
        event.sections.single.copy(
          rounds: [
            for (final r in event.sections.single.rounds)
              r.copy(byes: [...r.byes.where((b) => b.player != 'p4')]),
          ],
        ),
      ],
    );
    expect(ratingPackage(unrecorded, today: today), files);
    saveFixture('withdrawal-half-bye', event);
  });

  test('officials are credited in the header and every section', () {
    final event = _officials();
    validateEvent(event);
    expect(ratingPreflight(event, today: today), isEmpty);
    final files = ratingPackage(event, today: today);
    final date = DateTime(2024, 2, 28);
    expectDbfFraming(
      files['THEXPORT.DBF']!,
      fields: headerSchema,
      records: 1,
      date: date,
    );
    expectDbfFraming(
      files['TSEXPORT.DBF']!,
      fields: sectionSchema,
      records: 2,
      date: date,
    );
    final others = [for (var i = 1; i <= 28; i++) '${20000000 + i}'].join(',');
    expect(others, hasLength(251));
    expect(
      dbfRecords(files['THEXPORT.DBF']!),
      ' ${dbfCells([('2C', 5), ('MEOW $appVersion', 10), ('', 12), ('Byte contract', 35), ('2', 2), ('20240228', 8), ('20240228', 8), ('A6012345', 8), ('Boston', 21), ('MA', 2), ('02116', 10), ('USA', 21), ('N', 1), ('00123456', 8), ('00123457', 8), (others, 255)])}',
    );
    String section(String number, String name, String rounds, String last) =>
        ' ${dbfCells([('', 12), (number, 2), (name, 30), ('R', 1), ('G/90;d30', 40), ('00123456', 8), ('00123457', 8), ('S', 1), (rounds, 2), (last, 4), ('20240228', 8), ('20240228', 8), ('N', 1), ('N', 1), ('0', 3), ('N', 1)])}';
    expect(
      dbfRecords(files['TSEXPORT.DBF']!),
      section('1', 'Open', '2', '4') + section('2', 'Reserve', '1', '2'),
    );
    final p = {for (final p in event.players) p.id: p};
    expect(
      dbfRecords(files['TDEXPORT.DBF']!),
      [
        _detail(1, 1, p['p1']!, 'FAMILY1, GIVEN1', ['W3W', 'W2B']),
        _detail(1, 2, p['p2']!, 'FAMILY2, GIVEN2', ['D4B', 'L1W']),
        _detail(1, 3, p['p3']!, 'FAMILY3, GIVEN3', ['L1B', 'W4W']),
        _detail(1, 4, p['p4']!, 'FAMILY4, GIVEN4', ['D2W', 'L3B']),
        // Pair numbers restart in each section; one round leaves U0.
        _detail(2, 1, p['p5']!, 'FAMILY5, GIVEN5', ['L2W', 'U0']),
        _detail(2, 2, p['p6']!, 'FAMILY6, GIVEN6', ['W1B', 'U0']),
      ].join(),
    );
    // An empty section between them changes no byte.
    expect(
      ratingPackage(_officials(withEmptySection: true), today: today),
      files,
    );
    saveFixture('officials-sections', event);
  });

  test('a 29th other TD would overflow H_OTHER_TD and is refused', () {
    final event = _officials().copy(otherTdIds: _otherTds(29));
    expect(
      ratingPreflight(event, today: today),
      contains(
        'The other TDs list is longer than the report allows (255 characters). Correct it in Event details.',
      ),
    );
    expect(
      () => ratingPackage(event, today: today),
      throwsA(isA<TournamentException>()),
    );
  });

  group('text at its field width', () {
    test('is written whole, with no padding left', () {
      final event = _widest();
      validateEvent(event);
      expect(ratingPreflight(event, today: today), isEmpty);
      final files = ratingPackage(event, today: today);
      final header = readDbf(files['THEXPORT.DBF']!).$2.single;
      expect((header['H_NAME'], header['H_CITY']), (_longEvent, _longCity));
      expect(
        readDbf(files['TSEXPORT.DBF']!).$2.single['S_SEC_NAME'],
        _longSection,
      );
      final p = event.players.first;
      expect(
        dbfRecords(files['TDEXPORT.DBF']!),
        startsWith(_detail(1, 1, p, 'FEATHERSTONEHAUGH, ALEXANDRINA', ['D2W'])),
      );
      saveFixture('field-widths', event);
    });

    test('one character more is refused, never truncated', () {
      final event = _widest();
      Event withName(String name) => event.copy(
        players: [
          event.players.first.copy(name: name),
          event.players.last,
        ],
      );
      final cases = {
        event.copy(
          name: '${_longEvent}s',
        ): 'Event name is 36 characters; US Chess allows 35. Change it in Event details.',
        event.copy(
          city: '${_longCity}s',
        ): 'City is 22 characters; US Chess allows 21. Enter it under Report details.',
        event.copy(
          sections: [event.sections.single.copy(name: '${_longSection}s')],
        ): 'Section name "${_longSection}s" is 31 characters; US Chess allows 30. Rename the section.',
        withName(
          '${_longName}s',
        ): '${_longName}s: name is 31 characters on the rating report; US Chess allows 30. Set "Name on rating report" in the player panel.',
        // Folding can lengthen a name: 29 characters on screen, 31 reported.
        withName(
          'Alexandrina Featherstonehaugß',
        ): 'Alexandrina Featherstonehaugß: name is 31 characters on the rating report; US Chess allows 30. Set "Name on rating report" in the player panel.',
      };
      for (final MapEntry(key: invalid, value: message) in cases.entries) {
        expect(ratingPreflight(invalid, today: today), [message]);
        expect(
          () => ratingPackage(invalid, today: today),
          throwsA(isA<TournamentException>()),
          reason: message,
        );
      }
      // A report name within the width resolves the long derived one.
      final aliased = withName('${_longName}s').copy(
        players: [
          withName(
            '${_longName}s',
          ).players.first.copy(reportName: 'Featherstonehaughs, Alexandra'),
          event.players.last,
        ],
      );
      expect(ratingPreflight(aliased, today: today), isEmpty);
    });
  });

  test('four-digit pair numbers fill D_PAIR_NUM and S_LST_PAIR', () {
    final players = [for (var n = 1; n <= 1000; n++) syntheticPlayer(n)];
    final event = syntheticEvent(
      players: players,
      sections: [
        Section(
          id: 'large',
          name: 'Large',
          players: [for (final p in players) p.id],
          plannedRounds: 1,
          rounds: [
            Round(
              number: 1,
              games: [
                for (var n = 0; n < 500; n++)
                  _game(
                    'g$n',
                    players[n].id,
                    players[999 - n].id,
                    n + 1,
                    Outcome.whiteWin,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
    validateEvent(event);
    final files = ratingPackage(event, today: today);
    expect(readDbf(files['TSEXPORT.DBF']!).$2.single['S_LST_PAIR'], '1000');
    final records = dbfRecords(files['TDEXPORT.DBF']!);
    final size = 1 + 12 + 2 + 4 + 8 + 30 + 2 + 4 + 7;
    String record(int pair) =>
        records.substring((pair - 1) * size, pair * size);
    expect(record(1), _detail(1, 1, players[0], 'FAMILY1, GIVEN1', ['W1000W']));
    expect(
      record(500),
      _detail(1, 500, players[499], 'FAMILY500, GIVEN500', ['W501W']),
    );
    expect(
      record(1000),
      _detail(1, 1000, players[999], 'FAMILY1000, GIVEN1000', ['L1B']),
    );
  });

  test('a section of 10,000 entrants is refused', () {
    final players = [for (var n = 1; n <= 10000; n++) syntheticPlayer(n)];
    final event = syntheticEvent(
      players: players,
      sections: [
        Section(
          id: 'huge',
          name: 'Huge',
          players: [for (final p in players) p.id],
          plannedRounds: 1,
        ),
      ],
    );
    expect(
      ratingPreflight(event, today: today),
      contains(
        'Section Huge exceeds 32 reported rounds (double-game rounds count twice) or 9999 players.',
      ),
    );
  });

  test('D_RATING is the published rating, never an assigned one', () {
    final event = _ratingMix();
    validateEvent(event);
    expect(ratingPreflight(event, today: today), isEmpty);
    final files = ratingPackage(event, today: today);
    final p = event.players;
    expect(
      dbfRecords(files['TDEXPORT.DBF']!),
      [
        _detail(1, 1, p[0], 'FAMILY1, GIVEN1', ['W3W']),
        _detail(1, 2, p[1], 'FAMILY2, GIVEN2', ['W4B']),
        _detail(1, 3, p[2], 'FAMILY3, GIVEN3', ['L1B']),
        _detail(1, 4, p[3], 'FAMILY4, GIVEN4', ['L2W']),
      ].join(),
    );
    expect(readDbf(files['TDEXPORT.DBF']!).$2.map((d) => d['D_RATING']), [
      '4000',
      '850',
      '0',
      '0',
    ]);
    saveFixture('rating-mix', event);
  });

  group('players moved between sections', () {
    Event moved(int effectiveRound) => _officials().copy(
      transitions: [
        {
          'players': ['p6'],
          'target': 'reserve',
          'effectiveRound': effectiveRound,
          'reason': 'Moved down',
          'revision': 1,
        },
      ],
    );

    test('before play started are reported where they now play', () {
      final event = moved(1);
      expect(ratingPreflight(event, today: today), isEmpty);
      expect(
        ratingPackage(event, today: today),
        ratingPackage(_officials(), today: today),
      );
    });
  });
}
