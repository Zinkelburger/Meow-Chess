import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:path/path.dart' as p;

import 'dbf_importer_test.dart' show saveFixture;
import 'rating_contract_test.dart' show doubleBlitz, readDbf, today;

/// Byte-for-byte 2C contract: the dBASE III framing every DBF reader relies
/// on, golden records for a minimal event, and one package per section shape
/// (categories, double-game byes and forfeits, round robins with a bye).

Player _player(int i, {String state = 'MA', int rating = 1500}) => Player(
  id: 'p$i',
  name: 'Given$i Family$i',
  memberId: '${12345670 + i}',
  rating: rating,
  state: state,
);

Event _event({
  required List<Player> players,
  required List<Section> sections,
  String timeControl = 'G/90;d30',
}) => Event(
  id: 'bytes',
  name: 'Byte contract',
  date: '2024-02-28',
  timeControl: timeControl,
  tdId: '00123456',
  affiliateId: 'A6012345',
  city: 'Boston',
  state: 'MA',
  zip: '02116',
  players: players,
  sections: sections,
);

/// Two players, one decisive game: the smallest ratable report.
Event _minimal() {
  final players = [_player(1), _player(2, state: '', rating: 0)];
  return _event(
    players: players,
    sections: [
      Section(
        id: 's',
        name: 'Open',
        players: const ['p1', 'p2'],
        plannedRounds: 1,
        rounds: [
          Round(
            number: 1,
            games: [
              Game(
                id: 'g',
                white: 'p1',
                black: 'p2',
                board: 1,
                outcome: Outcome.whiteWin,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Asserts the dBASE III framing independently of [readDbf]: version byte,
/// last-update date, counts, descriptor layout, terminators, deletion flags,
/// printable ASCII payload and the exact file length.
void expectDbfFraming(
  Uint8List bytes, {
  required List<(String, int)> fields,
  required int records,
  required DateTime date,
}) {
  final view = ByteData.sublistView(bytes);
  final header = 32 + 32 * fields.length + 1;
  final size = 1 + fields.fold<int>(0, (n, f) => n + f.$2);
  expect(bytes[0], 3, reason: 'dBASE III without memo');
  expect(bytes.sublist(1, 4), [date.year - 1900, date.month, date.day]);
  expect(view.getUint32(4, Endian.little), records);
  expect(view.getUint16(8, Endian.little), header);
  expect(view.getUint16(10, Endian.little), size);
  expect(bytes.sublist(12, 32).every((b) => b == 0), isTrue);
  for (final (i, (name, width)) in fields.indexed) {
    final at = 32 + 32 * i;
    final descriptor = bytes.sublist(at, at + 32);
    expect(descriptor.sublist(0, 11), [
      ...ascii.encode(name),
      ...List.filled(11 - name.length, 0),
    ]);
    expect(descriptor[11], 'C'.codeUnitAt(0));
    expect(descriptor[16], width);
    expect(descriptor[17], 0, reason: '$name has no decimals');
    expect(descriptor.sublist(12, 16).every((b) => b == 0), isTrue);
    expect(descriptor.sublist(18).every((b) => b == 0), isTrue);
  }
  expect(bytes[header - 1], 13, reason: 'header terminator');
  expect(bytes.length, header + records * size + 1);
  expect(bytes.last, 26, reason: 'end-of-file marker');
  for (var r = 0; r < records; r++) {
    final at = header + r * size;
    expect(bytes[at], 32, reason: 'record $r is not deleted');
    expect(
      bytes.sublist(at, at + size).every((b) => b >= 32 && b <= 126),
      isTrue,
      reason: 'record $r is printable ASCII',
    );
  }
}

String _records(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final header = view.getUint16(8, Endian.little);
  return ascii.decode(bytes.sublist(header, bytes.length - 1));
}

const _header = [
  ('H_FORMAT', 5),
  ('H_PROGRAM', 10),
  ('H_EVENT_ID', 12),
  ('H_NAME', 35),
  ('H_TOT_SECT', 2),
  ('H_BEG_DATE', 8),
  ('H_END_DATE', 8),
  ('H_AFF_ID', 8),
  ('H_CITY', 21),
  ('H_STATE', 2),
  ('H_ZIPCODE', 10),
  ('H_COUNTRY', 21),
  ('H_SENDCROS', 1),
  ('H_CTD_ID', 8),
  ('H_ATD_ID', 8),
  ('H_OTHER_TD', 255),
];
const _section = [
  ('S_EVENT_ID', 12),
  ('S_SEC_NUM', 2),
  ('S_SEC_NAME', 30),
  ('S_R_SYSTEM', 1),
  ('S_TIMECTL', 40),
  ('S_CTD_ID', 8),
  ('S_ATD_ID', 8),
  ('S_TRN_TYPE', 1),
  ('S_TOT_RNDS', 2),
  ('S_LST_PAIR', 4),
  ('S_BEG_DATE', 8),
  ('S_END_DATE', 8),
  ('S_SCH_LVL', 1),
  ('S_GR_PRIX', 1),
  ('S_GP_PTS', 3),
  ('S_FIDE', 1),
];
List<(String, int)> _detail(int rounds) => [
  ('D_EVENT_ID', 12),
  ('D_SEC_NUM', 2),
  ('D_PAIR_NUM', 4),
  ('D_MEM_ID', 8),
  ('D_NAME', 30),
  ('D_STATE', 2),
  ('D_RATING', 4),
  for (var n = 1; n <= rounds; n++) ('D_RND${n.toString().padLeft(2, '0')}', 7),
];

String _cells(List<(String, int)> values) =>
    values.map((v) => v.$1.padRight(v.$2)).join();

void main() {
  group('golden bytes', () {
    test('minimal event: every record byte as US Chess reads it', () {
      final event = _minimal();
      expect(ratingPreflight(event, today: today), isEmpty);
      final files = ratingPackage(event, today: today);
      final date = DateTime(2024, 2, 28);
      expectDbfFraming(
        files['THEXPORT.DBF']!,
        fields: _header,
        records: 1,
        date: date,
      );
      expectDbfFraming(
        files['TSEXPORT.DBF']!,
        fields: _section,
        records: 1,
        date: date,
      );
      expectDbfFraming(
        files['TDEXPORT.DBF']!,
        fields: _detail(1),
        records: 2,
        date: date,
      );
      expect(
        _records(files['THEXPORT.DBF']!),
        ' ${_cells([('2C', 5), ('MEOW $appVersion', 10), ('', 12), ('Byte contract', 35), ('1', 2), ('20240228', 8), ('20240228', 8), ('A6012345', 8), ('Boston', 21), ('MA', 2), ('02116', 10), ('USA', 21), ('N', 1), ('00123456', 8), ('', 8), ('', 255)])}',
      );
      expect(
        _records(files['TSEXPORT.DBF']!),
        ' ${_cells([('', 12), ('1', 2), ('Open', 30), ('R', 1), ('G/90;d30', 40), ('00123456', 8), ('', 8), ('S', 1), ('1', 2), ('2', 4), ('20240228', 8), ('20240228', 8), ('N', 1), ('N', 1), ('0', 3), ('N', 1)])}',
      );
      // Numbers are left-justified and blank-padded, as SwissSys writes them;
      // an unrated player reports 0 and a missing state stays blank.
      expect(
        _records(files['TDEXPORT.DBF']!),
        ' ${_cells([('', 12), ('1', 2), ('1', 4), ('12345671', 8), ('FAMILY1, GIVEN1', 30), ('MA', 2), ('1500', 4), ('W2W', 7)])}'
        ' ${_cells([('', 12), ('1', 2), ('2', 4), ('12345672', 8), ('FAMILY2, GIVEN2', 30), ('', 2), ('0', 4), ('L1B', 7)])}',
      );
    });

    test('a multi-day event stamps the last day in the header bytes', () {
      final event = _minimal().copy(date: '2023-12-31', endDate: '2024-01-02');
      final files = ratingPackage(event, today: today);
      for (final bytes in files.values) {
        expect(bytes.sublist(1, 4), [124, 1, 2]);
      }
      final header = readDbf(files['THEXPORT.DBF']!).$2.single;
      expect(
        (header['H_BEG_DATE'], header['H_END_DATE']),
        ('20231231', '20240102'),
      );
    });

    test('double-game framing holds for every file', () {
      final event = doubleBlitz();
      final files = ratingPackage(event, today: today);
      final date = DateTime(2024, 2, 28);
      expectDbfFraming(
        files['THEXPORT.DBF']!,
        fields: _header,
        records: 1,
        date: date,
      );
      expectDbfFraming(
        files['TSEXPORT.DBF']!,
        fields: _section,
        records: 1,
        date: date,
      );
      expectDbfFraming(
        files['TDEXPORT.DBF']!,
        fields: _detail(4),
        records: 4,
        date: date,
      );
      final header = readDbf(files['THEXPORT.DBF']!).$2.single;
      expect(header['H_ATD_ID'], '00123457');
      expect(header['H_OTHER_TD'], '00123458,00123459');
    });
  });

  test('each rule 5C category gets its own section system and control', () {
    final players = [for (var i = 0; i < 8; i++) _player(i)];
    Section section(int n, String control) => Section(
      id: 's$n',
      name: 'Section $n',
      timeControl: control,
      players: ['p${2 * n}', 'p${2 * n + 1}'],
      plannedRounds: 1,
      rounds: [
        Round(
          number: 1,
          games: [
            Game(
              id: 'g$n',
              white: 'p${2 * n}',
              black: 'p${2 * n + 1}',
              board: n + 1,
              outcome: Outcome.draw,
            ),
          ],
        ),
      ],
    );
    final event = _event(
      players: players,
      sections: [
        section(0, 'G/90;d30'),
        section(1, 'G/45 d5'),
        section(2, 'G/20;+5'),
        section(3, 'G/3;+2'),
      ],
    );
    expect(ratingPreflight(event, today: today), isEmpty);
    final files = ratingPackage(event, today: today);
    final rows = readDbf(files['TSEXPORT.DBF']!).$2;
    expect(rows.map((r) => (r['S_R_SYSTEM'], r['S_TIMECTL'])), [
      ('R', 'G/90;d30'),
      ('D', 'G/45;d5'),
      ('Q', 'G/20;+5'),
      // 2C has no Blitz letter; US Chess rated SwissSys's D by time control.
      ('D', 'G/3;+2'),
    ]);
    final manifest = ratingManifest(event, files);
    expect(manifest['ratingSystem'], isNull, reason: 'systems differ');
    expect(manifest['timeControl'], isNull, reason: 'controls differ');
    expect(
      [for (final s in manifest['sections'] as List) s['category']],
      ['regular', 'dual', 'quick', 'blitz'],
    );
    expect(manifest['files'], {
      for (final MapEntry(:key, :value) in files.entries) key: value.length,
    });
    saveFixture('categories', event);
  });

  test('double-game byes split across legs and forfeits keep no opponent', () {
    final players = [for (var i = 0; i < 8; i++) _player(i)];
    Game g(String id, String w, String b, int leg, Outcome o) => Game(
      id: id,
      white: w,
      black: b,
      board: id == 'a' || id == 'b' ? 1 : 2,
      leg: leg,
      outcome: o,
    );
    final event = _event(
      timeControl: 'G/5;d0',
      players: players,
      sections: [
        Section(
          id: 's',
          name: 'Double',
          doubleGames: true,
          plannedRounds: 1,
          players: [for (final p in players) p.id],
          rounds: [
            Round(
              number: 1,
              games: [
                g('a', 'p0', 'p1', 1, Outcome.whiteForfeit),
                g('b', 'p1', 'p0', 2, Outcome.doubleForfeit),
                g('c', 'p6', 'p7', 1, Outcome.draw),
                g('d', 'p7', 'p6', 2, Outcome.whiteWin),
              ],
              byes: const [
                // Half-points: 3 is a full and a half bye, 1 a half and none.
                ByeAward('p2', 3, 'Requested'),
                ByeAward('p3', 1, 'Requested'),
                ByeAward('p4', 0, 'Requested'),
                ByeAward('p5', 4, 'Allocated', allocated: true),
              ],
            ),
          ],
        ),
      ],
    );
    validateEvent(event);
    expect(ratingPreflight(event, today: today), isEmpty);
    final files = ratingPackage(event, today: today);
    final section = readDbf(files['TSEXPORT.DBF']!).$2.single;
    expect(
      (section['S_TRN_TYPE'], section['S_TOT_RNDS']),
      ('S', '2'),
      reason: 'a double-game round is reported as two Swiss rounds',
    );
    final rows = readDbf(files['TDEXPORT.DBF']!).$2;
    expect(rows.map((r) => (r['D_RND01'], r['D_RND02'])), [
      ('X0', 'F0'),
      ('F0', 'F0'),
      ('B0', 'H0'),
      ('H0', 'U0'),
      ('U0', 'U0'),
      ('B0', 'B0'),
      ('D8W', 'L8B'),
      ('D7B', 'W7W'),
    ]);
    saveFixture('double-byes-forfeits', event);
  });

  test('a three-player round robin reports its bye as R with U0 cells', () {
    final players = [for (var i = 0; i < 3; i++) _player(i)];
    final ids = [for (final p in players) p.id];
    final schedule = roundRobinSchedule(ids);
    final event = _event(
      players: players,
      sections: [
        Section(
          id: 'rr',
          name: 'Round robin',
          format: Format.roundRobin,
          players: ids,
          plannedRounds: schedule.length,
          rounds: [
            for (final (index, pairs) in schedule.indexed)
              Round(
                number: index + 1,
                games: [
                  for (final (board, pair) in pairs.indexed)
                    if (pair.$1 != null && pair.$2 != null)
                      Game(
                        id: '$index-$board',
                        white: pair.$1!,
                        black: pair.$2!,
                        board: board + 1,
                        outcome: Outcome.blackWin,
                      ),
                ],
              ),
          ],
        ),
      ],
    );
    validateEvent(event);
    expect(ratingPreflight(event, today: today), isEmpty);
    final files = ratingPackage(event, today: today);
    final section = readDbf(files['TSEXPORT.DBF']!).$2.single;
    expect(section['S_TRN_TYPE'], 'R');
    expect(section['S_TOT_RNDS'], '${schedule.length}');
    final rows = readDbf(files['TDEXPORT.DBF']!).$2;
    for (final row in rows) {
      final cells = [
        for (var n = 1; n <= schedule.length; n++)
          row['D_RND${n.toString().padLeft(2, '0')}']!,
      ];
      // Each player sits out exactly one round and meets both others once.
      expect(cells.where((c) => c == 'U0'), hasLength(1));
      expect({
        for (final c in cells.where((c) => c != 'U0')) c.substring(1, 2),
      }, hasLength(2));
    }
    saveFixture('round-robin-bye', event);
  });

  group('encodeDbf refuses rather than truncates', () {
    const fields = [DbfField('NAME', 4)];
    final date = DateTime(2024, 1, 1);
    test('values wider than the field', () {
      expect(
        () => encodeDbf(fields, [
          {'NAME': 'TOOLONG'},
        ], date),
        throwsA(isA<TournamentException>()),
      );
    });
    test('non-ASCII and control characters', () {
      for (final value in ['José', 'A\tB', 'A\x7f']) {
        expect(
          () => encodeDbf(fields, [
            {'NAME': value},
          ], date),
          throwsA(isA<TournamentException>()),
          reason: value,
        );
      }
    });
    test('header dates outside the one-byte year range', () {
      for (final year in [1899, 2156]) {
        expect(
          () => encodeDbf(fields, const [], DateTime(year)),
          throwsA(isA<TournamentException>()),
        );
      }
      expect(encodeDbf(fields, const [], DateTime(2155, 12, 31))[1], 255);
    });
    test('invalid schemas', () {
      for (final bad in [
        const DbfField('ELEVENCHARS', 4),
        const DbfField('ZERO', 0),
        const DbfField('WIDE', 256),
      ]) {
        expect(
          () => encodeDbf([bad], const [], date),
          throwsA(isA<TournamentException>()),
          reason: bad.name,
        );
      }
    });
    test('an empty table is a valid file', () {
      final bytes = encodeDbf(fields, const [], date);
      expectDbfFraming(bytes, fields: [('NAME', 4)], records: 0, date: date);
    });
  });

  test('the written package is the generated bytes plus a manifest', () async {
    final event = _minimal();
    final dir = await Directory.systemTemp.createTemp('meow-dbf-bytes-');
    addTearDown(() => dir.delete(recursive: true));
    final folder = await writeRatingPackage(event, dir.path);
    expect(p.dirname(folder), dir.path);
    final expected = ratingPackage(event);
    expect(
      Directory(folder).listSync().map((f) => p.basename(f.path)).toSet(),
      {...expected.keys, 'manifest.json'},
    );
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(File(p.join(folder, key)).readAsBytesSync(), value, reason: key);
    }
    final manifest = jsonDecode(
      File(p.join(folder, 'manifest.json')).readAsStringSync(),
    );
    expect(manifest['ratingSystem'], 'R');
    expect(manifest['timeControl'], 'G/90;d30');
    expect(dir.listSync(), hasLength(1), reason: 'no staging left behind');
  });
}
