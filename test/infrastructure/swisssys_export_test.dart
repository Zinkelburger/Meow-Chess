import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/swisssys_export.dart';
import 'package:meow_chess/infrastructure/xls_writer.dart';
import 'package:path/path.dart' as p;

import '../xls_reader.dart';

/// Six players in rating order. The fifth asked for a half-point bye in
/// round 1 and the second for one in round 3.
Event open({List<Round> rounds = const [], Format format = Format.swiss}) =>
    Event(
      id: 'e',
      name: 'Tornado #150',
      date: '2026-11-21',
      timeControl: 'G/60 d5',
      players: [
        Player(
          id: 'p1',
          name: 'Ada Stone',
          memberId: '12000001',
          rating: 2100,
          state: 'VT',
          membershipEvidence: const {'expiration': '2027-04-30'},
        ),
        Player(id: 'p2', name: 'Ben de la Cruz', rating: 1900, byes: {3: 1}),
        Player(id: 'p3', name: 'Stone, Cy', rating: 1700, pairingRating: 1750),
        Player(id: 'p4', name: 'Dee Park Jr', rating: 1500),
        Player(id: 'p5', name: 'Eli Ng', rating: 1300, byes: {1: 1}),
        Player(id: 'p6', name: 'Fay Oduya', rating: 0),
      ],
      sections: [
        Section(
          id: 's',
          name: 'Open',
          format: format,
          players: ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
          plannedRounds: 4,
          boardStart: 11,
          rounds: rounds,
        ),
      ],
    );

/// Round 1: two boards, the requested half-point bye, and the odd player's
/// full-point bye.
Round round1({
  Outcome first = Outcome.unreported,
  Outcome second = Outcome.unreported,
}) => Round(
  number: 1,
  games: [
    Game(id: 'g2', white: 'p4', black: 'p2', board: 12, outcome: second),
    Game(id: 'g1', white: 'p1', black: 'p3', board: 11, outcome: first),
  ],
  byes: const [
    ByeAward('p5', 1, 'requested'),
    ByeAward('p6', 2, 'odd player', allocated: true),
  ],
);

Map<String, List<List<Object?>>> sheets(Event e, {int? round}) => {
  for (final entry in readXls(
    swissSysSection(e, e.sections.single, round: round),
  ).entries)
    entry.key: xlsRows(entry.value),
};

/// One row of [sheet] by its column headings.
Map<String, Object?> named(List<List<Object?>> sheet, int row) => {
  for (final (i, heading) in sheet.first.indexed)
    if (heading != null) '$heading': sheet[row].elementAtOrNull(i),
};

void main() {
  test('a paired round is the file SwissSys writes after pairing', () {
    final e = open(rounds: [round1()]);
    expect(swissSysFileName(e.sections.single), 'Open.S1A');
    final file = sheets(e);
    expect(file.keys, ['Settings', 'Players', 'Results', 'Tables']);

    // Boards in order, then the pairing's bye, then the requested one. The
    // list is kept three times over.
    expect(file['Tables'], [
      [
        'WHITE',
        'BLACK',
        'BD',
        'NAT_WH',
        'NAT_BL',
        'NAT_BD',
        'A_NAT_WH',
        'A_NAT_BL',
        'A_NAT_BD',
      ],
      [1.0, 3.0, 11.0, 1.0, 3.0, 11.0, 1.0, 3.0, 11.0],
      [4.0, 2.0, 12.0, 4.0, 2.0, 12.0, 4.0, 2.0, 12.0],
      [6.0, -1.0, 0.0, 6.0, -1.0, 0.0, 6.0, -1.0, 0.0],
      [5.0, -1.0, 0.0, 5.0, -1.0, 0.0, 5.0, -1.0, 0.0],
    ]);

    expect(file['Results'], [
      ['PLAYER', 'OP1', 'CLR1', 'RES1', 'RES_CH1', 'GM_WINS1'],
      [1.0, 3.0, 1.0, 0.0, ' ', 0.0],
      [2.0, 4.0, -1.0, 0.0, ' ', 0.0],
      [3.0, 1.0, -1.0, 0.0, ' ', 0.0],
      [4.0, 2.0, 1.0, 0.0, ' ', 0.0],
      [5.0, -1.0, 0.0, 1.0, 'H', 0.0],
      [6.0, -1.0, 0.0, 2.0, 'B', 0.0],
    ]);

    final settings = file['Settings']!;
    expect(settings.first, hasLength(44));
    expect(named(settings, 1), {
      'FILE_TYPE': 'SWISSSYS',
      'VERSION': '9.14',
      'PLR_CNT': 6.0,
      'RDS_PLD': 0.0,
      'RDS_PRD': 1.0,
      'BYES': 5.0,
      'TM_BYES': null,
      'QUICK': -1.0,
      '1ST_BD': 11.0,
      'LOW': 0.0,
      'HIGH': 9999.0,
      'LAST_RD': 0.0,
      'COIN': 1.0,
      'TM_CUT': 999.0,
      'ALL_IN': true,
      '1ST_TIME': true,
      'SORTED': true,
      'ACCEL': false,
      'USE_TMS': false,
      'BLITZ': false,
      'TM_PAIRS': true,
      'FR_TM': false,
      'R_ROBIN': false,
      'TBL_SET': false,
      'BERGER': false,
      'FR_TBL': false,
      'LOGIC': true,
      'GOT_TMS': true,
      'SEC_TITLE': 'Open',
      'SEC_TIME': '',
      'TNMT_TITLE': 'Tornado #150',
      'TNMT_TIME': 'G/60 d5',
      'LADDER': false,
      'DIVIDED': false,
      'LOW GRD': 0.0,
      'HIGH GRD': 99.0,
      // Two columns share this heading; the later one wins here.
      '-1': false,
      'DBL_ACCEL': false,
      'TEAMS_ONLY': false,
      'RATING_TO_USE': 0.0,
      'EXCLUDE_BATCH': false,
      'EXCLUDE_RATINGS': false,
      'EXCLUDE_KRAUSE': false,
    });
    expect(settings[1][36], 4.0, reason: 'the round count');
    // The second bye of the round sits under the first, alone on its row.
    expect(settings[2].whereType<Object>(), [6.0]);
    expect(settings[2][5], 6.0);

    final players = file['Players']!;
    expect(players.first, hasLength(42));
    expect(players, hasLength(7));
    // Every player cell is there, most as empty text.
    expect(players.expand((row) => row), everyElement(isNotNull));
    final ada = named(players, 1);
    expect(ada['NAME'], 'STONE,ADA');
    expect(ada['ID'], '12000001');
    expect(ada['RATING'], 2100.0);
    expect(ada['EXP1'], '04/30/2027');
    expect(ada['STATE'], 'VT');
    expect(ada['CLASS'], ' ');
    expect(ada['SCORE'], '0');
    expect(ada['RES_CH'], ' ');
    expect(ada['PAIRED'], true);
    expect(ada['BOARDS'], '11');
    expect(ada['ADJ_SCORES'], '0');
    expect(ada['ADV_BYES'], '');
    expect(ada['SECTION_NUM'], 0.0);
    expect(
      [for (var r = 1; r < 7; r++) named(players, r)['NAME']],
      [
        'STONE,ADA',
        'DE LA CRUZ,BEN',
        'STONE,CY',
        'PARK,DEE JR',
        'NG,ELI',
        'ODUYA,FAY',
      ],
    );
    expect(named(players, 2)['ADV_BYES'], '3 ');
    expect(named(players, 3)['RATING'], 1750.0, reason: 'the pairing rating');
    final half = named(players, 5), full = named(players, 6);
    expect(
      [half['SCORE'], half['RES_CH'], half['PAIRED'], half['BOARDS']],
      ['1', '½', false, '0'],
    );
    expect([half['ADV_BYES'], half['ADJ_SCORES']], ['1 ', '1']);
    expect(
      [full['SCORE'], full['RES_CH'], full['PAIRED'], full['BOARDS']],
      ['2', '1', false, '0'],
    );
    expect(full['ADJ_SCORES'], '0');
  });

  test('a withdrawn player is flagged, everyone else left blank', () {
    final e = open(rounds: [round1()]);
    final withdrawn = e.copy(
      players: [
        for (final p in e.players) p.id == 'p4' ? p.copy(withdrawn: true) : p,
      ],
    );
    final players = sheets(withdrawn)['Players']!;
    expect(
      [for (var r = 1; r < 7; r++) named(players, r)['WITHDREW']],
      ['', '', '', true, '', ''],
    );
  });

  test('before round 1 the file has players and an empty board list', () {
    final e = open();
    expect(swissSysFileName(e.sections.single), 'Open.S0C');
    final file = sheets(e);
    expect(file['Results'], isEmpty);
    expect(file['Tables'], [
      [
        null,
        null,
        null,
        'NAT_WH',
        'NAT_BL',
        'NAT_BD',
        'A_NAT_WH',
        'A_NAT_BL',
        'A_NAT_BD',
      ],
    ]);
    final settings = named(file['Settings']!, 1);
    expect(
      [settings['RDS_PRD'], settings['BYES'], settings['COIN']],
      [0.0, null, 10.0],
    );
    expect([settings['ALL_IN'], settings['LOGIC']], [false, false]);
    expect(file['Settings'], hasLength(2));
    final ada = named(file['Players']!, 1);
    expect(
      [ada['SCORE'], ada['PAIRED'], ada['BOARDS'], ada['ADJ_SCORES']],
      ['0', false, '', ''],
    );
  });

  test('later rounds carry the earlier results and running scores', () {
    final round2 = Round(
      number: 2,
      games: const [
        Game(id: 'h1', white: 'p3', black: 'p6', board: 11),
        Game(id: 'h2', white: 'p2', black: 'p5', board: 12),
      ],
      // The first player withdrew; the fourth sits out for nothing.
      byes: const [ByeAward('p4', 0, 'requested')],
    );
    final e = open(
      rounds: [
        round1(first: Outcome.draw, second: Outcome.blackForfeit),
        round2,
      ],
    );
    expect(swissSysFileName(e.sections.single), 'Open.S2A');
    final file = sheets(e);
    expect(file['Results']!.first, [
      'PLAYER',
      'OP1',
      'CLR1',
      'RES1',
      'RES_CH1',
      'GM_WINS1',
      'OP2',
      'CLR2',
      'RES2',
      'RES_CH2',
      'GM_WINS2',
    ]);
    expect(file['Results']!.skip(1), [
      [1.0, 3.0, 1.0, 1.0, 'D', 0.0, -1.0, 0.0, 0.0, 'U', 0.0],
      [2.0, 4.0, -1.0, 2.0, 'X', 0.0, 5.0, 1.0, 0.0, ' ', 0.0],
      [3.0, 1.0, -1.0, 1.0, 'D', 0.0, 6.0, 1.0, 0.0, ' ', 0.0],
      [4.0, 2.0, 1.0, 0.0, 'F', 0.0, -1.0, 0.0, 0.0, 'U', 0.0],
      [5.0, -1.0, 0.0, 1.0, 'H', 0.0, 2.0, -1.0, 0.0, ' ', 0.0],
      [6.0, -1.0, 0.0, 2.0, 'B', 0.0, 3.0, -1.0, 0.0, ' ', 0.0],
    ]);
    final settings = named(file['Settings']!, 1);
    expect(
      [settings['RDS_PLD'], settings['RDS_PRD'], settings['BYES']],
      [1.0, 2.0, 4.0],
    );
    final players = file['Players']!;
    expect(
      [for (var r = 1; r < 7; r++) named(players, r)['SCORE']],
      ['1', '2', '1', '0', '1', '2'],
    );
    expect(
      [for (var r = 1; r < 7; r++) named(players, r)['BOARDS']],
      ['0', '12', '11', '0', '12', '11'],
    );
    expect(file['Tables']!.skip(1).map((row) => row.take(3)), [
      [3.0, 6.0, 11.0],
      [2.0, 5.0, 12.0],
      [4.0, -1.0, 0.0],
    ]);

    // Asking for round 1 leaves round 2 out, and round 1 is complete.
    expect(swissSysFileName(e.sections.single, round: 1), 'Open.S1C');
    final earlier = sheets(e, round: 1);
    expect(earlier['Results']!.first, hasLength(6));
    expect(named(earlier['Settings']!, 1)['RDS_PLD'], 1.0);
    final ada = named(earlier['Players']!, 1);
    expect([ada['SCORE'], ada['RES_CH']], ['1', '½']);
    expect(named(earlier['Players']!, 2)['RES_CH'], '1');
    expect(named(earlier['Players']!, 4)['RES_CH'], '0');
  });

  test('a quad shows the first round still being played', () {
    final e = open(
      format: Format.roundRobin,
      rounds: [
        round1(first: Outcome.whiteWin, second: Outcome.draw),
        Round(
          number: 2,
          games: const [Game(id: 'h', white: 'p2', black: 'p1', board: 11)],
        ),
        Round(
          number: 3,
          games: const [Game(id: 'i', white: 'p1', black: 'p4', board: 11)],
        ),
      ],
    );
    expect(swissSysRound(e.sections.single), 2);
    expect(swissSysFileName(e.sections.single), 'Open.S2A');
    expect(named(sheets(e)['Settings']!, 1)['R_ROBIN'], true);
  });

  test('sections SwissSys cannot describe are left out', () {
    final e = open(rounds: [round1()]);
    final mixed = e.copy(
      sections: [
        e.sections.single,
        Section(
          id: 'l',
          name: 'Ladder',
          format: Format.ladder,
          players: const [],
        ),
        Section(id: 'u', name: 'Open', players: const []),
        Section(id: 'w', name: 'open', players: const []),
        Section(id: 'v', name: 'U1200: Sat/Sun', players: const []),
      ],
    );
    // Sections sharing a name and a round must not share a file.
    expect(swissSysFiles(mixed).keys, [
      'Open.S1A',
      'Open.S0C',
      'open (2).S0C',
      'U1200 Sat Sun.S0C',
    ]);
    expect(swissSysFiles(mixed, sections: ['u']).keys, ['Open.S0C']);
    // A round the section does not have falls back to its current one.
    expect(swissSysFiles(mixed, rounds: {'s': 7, 'u': 1}).keys.take(2), [
      'Open.S1A',
      'Open.S0C',
    ]);
    expect(
      () => swissSysSection(mixed, mixed.sections[1]),
      throwsA(isA<TournamentException>()),
    );
  });

  test('files are written into the folder under their SwissSys names', () {
    final dir = Directory.systemTemp.createTempSync('meow-swisssys-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final e = open(rounds: [round1()]);
    final written = writeSwissSysFiles(swissSysFiles(e), dir.path);
    expect(written, [p.join(dir.path, 'Open.S1A')]);
    // Saving the round again replaces the file.
    writeSwissSysFiles(swissSysFiles(e), dir.path);
    expect(dir.listSync().map((f) => p.basename(f.path)), ['Open.S1A']);
    expect(
      readXls(File(written.single).readAsBytesSync()).keys,
      contains('Tables'),
    );
    expect(
      () => writeSwissSysFiles(swissSysFiles(e), p.join(dir.path, 'missing')),
      throwsA(isA<TournamentException>()),
    );
  });

  group('xls workbook', () {
    test('is an OLE2 file of whole sectors holding typed cells', () {
      final bytes = xlsWorkbook([
        const XlsSheet('One', [
          ['text', 1.5, true, null, false, -1, ''],
        ]),
        const XlsSheet('Empty', []),
      ]);
      expect(bytes.sublist(0, 8), [
        0xd0,
        0xcf,
        0x11,
        0xe0,
        0xa1,
        0xb1,
        0x1a,
        0xe1,
      ]);
      expect(bytes.length % 512, 0);
      final book = readXls(bytes);
      expect(book.keys, ['One', 'Empty']);
      expect(xlsRows(book['One']!), [
        ['text', 1.5, true, null, false, -1.0, ''],
      ]);
      expect(book['Empty'], isEmpty);
    });

    test('holds names beyond Latin-1 and more text than one record', () {
      // Enough distinct strings to need several string-table records and
      // more than one allocation-table sector.
      final rows = [
        for (var r = 0; r < 3000; r++)
          ['Player number $r of the long section', 'Żółć Łukasz $r', '½', r],
      ];
      final bytes = xlsWorkbook([XlsSheet('Players', rows)]);
      expect(bytes.length, greaterThan(128 * 512));
      expect(xlsRows(readXls(bytes)['Players']!), [
        for (final row in rows)
          [row[0], row[1], row[2], (row[3] as int).toDouble()],
      ]);
    });

    test('refuses what the format cannot hold', () {
      expect(
        () => xlsWorkbook([
          XlsSheet('Wide', [List<Object?>.filled(257, 1)]),
        ]),
        throwsArgumentError,
      );
      expect(
        () => xlsWorkbook([
          XlsSheet('Long', [
            ['x' * 4001],
          ]),
        ]),
        throwsArgumentError,
      );
      expect(() => xlsWorkbook([const XlsSheet('', [])]), throwsArgumentError);
    });
  });
}
