import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/us_chess.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:path/path.dart' as p;

/// Export checks compare dates against this day, not the machine clock.
final today = DateTime(2024, 3, 15);

/// Two-word ASCII names derive `FAMILY, GIVEN`; the verifier re-derives them
/// independently. Player 1 checks accent folding and player 2 an explicit
/// report name.
String fixtureName(int i) => switch (i) {
  1 => 'José Álvarez',
  _ => 'Given$i Family$i',
};

// A serialization fixture, not a claim that these results form a rated event.
// Two sections exercise section-local pairing numbers; 12 rounds catch the
// obsolete ten-round/pointer DBF layout; every outcome and bye code is present.
Event exportFixture() {
  final players = [
    for (var i = 0; i < 30; i++)
      Player(
        id: 'p$i',
        name: fixtureName(i),
        memberId: '${123456 + i}'.padLeft(8, '0'),
        rating: i == 0 ? 0 : 1800 - i * 10,
        state: i.isEven ? 'MA' : 'NH',
        reportName: i == 2 ? 'Family-Smith, Given' : '',
      ),
  ];
  final sections = [
    for (var s = 0; s < 2; s++)
      Section(
        id: 's$s',
        name: 'Section $s',
        plannedRounds: 12,
        players: players.skip(s * 15).take(15).map((p) => p.id).toList(),
        boardStart: 1 + s * 8,
        rounds: [
          for (final (r, pairs) in roundRobinSchedule(
            players.skip(s * 15).take(15).map((p) => p.id).toList(),
          ).take(12).indexed)
            Round(
              number: r + 1,
              games: [
                for (final (b, pair) in pairs.indexed)
                  if (pair.$1 != null && pair.$2 != null)
                    Game(
                      id: '$s-$r-$b',
                      white: pair.$1!,
                      black: pair.$2!,
                      board: 1 + s * 8 + b,
                      outcome: const [
                        Outcome.whiteWin,
                        Outcome.draw,
                        Outcome.blackWin,
                        Outcome.whiteForfeit,
                        Outcome.blackForfeit,
                        Outcome.doubleForfeit,
                      ][(b + r) % 6],
                    ),
              ],
              byes: [
                for (final pair in pairs)
                  if (pair.$1 == null || pair.$2 == null)
                    ByeAward(
                      (pair.$1 ?? pair.$2)!,
                      r % 3,
                      'Fixture bye',
                      allocated: r % 3 == 2,
                    ),
              ],
            ),
        ],
      ),
  ];
  return Event(
    id: 'export-contract',
    name: 'Synthetic export contract',
    date: '2024-02-28',
    endDate: '2024-02-29',
    timeControl: 'G/60;d5',
    tdId: '00123456',
    affiliateId: 'A6012345',
    city: 'Boston',
    state: 'MA',
    zip: '02116-1234',
    players: players,
    sections: sections,
  );
}

/// A minimal independent reader: field layout and trimmed values per record.
(List<(String, String, int)>, List<Map<String, String>>) readDbf(
  Uint8List bytes,
) {
  final view = ByteData.sublistView(bytes);
  final count = view.getUint32(4, Endian.little),
      header = view.getUint16(8, Endian.little),
      size = view.getUint16(10, Endian.little);
  final fields = <(String, String, int)>[];
  for (var at = 32; bytes[at] != 13; at += 32) {
    final name = ascii.decode(
      bytes.sublist(at, at + 11).takeWhile((b) => b != 0).toList(),
    );
    fields.add((name, String.fromCharCode(bytes[at + 11]), bytes[at + 16]));
  }
  final rows = <Map<String, String>>[];
  for (var r = 0; r < count; r++) {
    var at = header + r * size + 1;
    final row = <String, String>{};
    for (final (name, _, width) in fields) {
      row[name] = ascii.decode(bytes.sublist(at, at + width)).trimRight();
      at += width;
    }
    rows.add(row);
  }
  return (fields, rows);
}

Event withPlayer(Event e, int index, Player Function(Player) change) => e.copy(
  players: [for (final (i, p) in e.players.indexed) i == index ? change(p) : p],
);

void main() {
  test('fixture passes every check', () {
    final event = exportFixture();
    validateEvent(event);
    expect(ratingPreflight(event, today: today), isEmpty);
  });

  test('2C package covers all outcomes, byes, sections and round 12', () {
    final event = exportFixture();
    final files = ratingPackage(event, today: today);
    expect(
      files.keys,
      unorderedEquals(['THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF']),
    );
    expect(event.games.map((g) => g.outcome).toSet(), hasLength(6));
    if (Platform.environment['MEOW_EXPORT_FIXTURES'] == '1') {
      final folder = Directory('artifacts/dbf-contract')
        ..createSync(recursive: true);
      for (final file in files.entries) {
        File(p.join(folder.path, file.key)).writeAsBytesSync(file.value);
      }
      File(
        p.join(folder.path, 'expected-event.json'),
      ).writeAsStringSync(event.encode());
    }
  });

  test('field layout and values follow the 2C specification', () {
    final files = ratingPackage(exportFixture(), today: today);
    final (hFields, header) = readDbf(files['THEXPORT.DBF']!);
    final (sFields, sections) = readDbf(files['TSEXPORT.DBF']!);
    final (dFields, details) = readDbf(files['TDEXPORT.DBF']!);
    expect(hFields, [
      ('H_FORMAT', 'C', 5), ('H_PROGRAM', 'C', 10), ('H_EVENT_ID', 'C', 12),
      ('H_NAME', 'C', 35), ('H_TOT_SECT', 'C', 2), ('H_BEG_DATE', 'D', 8),
      ('H_END_DATE', 'D', 8), ('H_AFF_ID', 'C', 8), ('H_CITY', 'C', 21),
      ('H_STATE', 'C', 2), ('H_ZIPCODE', 'C', 10), ('H_COUNTRY', 'C', 21),
      ('H_SENDCROS', 'C', 1), ('H_CTD_ID', 'C', 8), ('H_ATD_ID', 'C', 8),
      // 254, not the 255 in 2C: the dBase III limit for character fields.
      ('H_OTHER_TD', 'C', 254),
    ]);
    expect(sFields.map((f) => f.$1), [
      'S_EVENT_ID',
      'S_SEC_NUM',
      'S_SEC_NAME',
      'S_R_SYSTEM',
      'S_TIMECTL',
      'S_CTD_ID',
      'S_ATD_ID',
      'S_TRN_TYPE',
      'S_TOT_RNDS',
      'S_LST_PAIR',
      'S_BEG_DATE',
      'S_END_DATE',
      'S_SCH_LVL',
      'S_GR_PRIX',
      'S_GP_PTS',
      'S_FIDE',
    ]);
    expect(dFields.take(7).map((f) => f.$1), [
      'D_EVENT_ID',
      'D_SEC_NUM',
      'D_PAIR_NUM',
      'D_MEM_ID',
      'D_NAME',
      'D_STATE',
      'D_RATING',
    ]);
    expect(dFields.skip(7).map((f) => f.$1), [
      for (var i = 1; i <= 12; i++) 'D_RND${i.toString().padLeft(2, '0')}',
    ]);
    expect(header.single, {
      'H_FORMAT': '2C',
      'H_PROGRAM': 'MEOW $appVersion',
      'H_EVENT_ID': 'MEOW',
      'H_NAME': 'Synthetic export contract',
      'H_TOT_SECT': '2',
      'H_BEG_DATE': '20240228',
      'H_END_DATE': '20240229',
      'H_AFF_ID': 'A6012345',
      'H_CITY': 'Boston',
      'H_STATE': 'MA',
      'H_ZIPCODE': '02116-1234',
      'H_COUNTRY': 'USA',
      'H_SENDCROS': 'N',
      'H_CTD_ID': '00123456',
      'H_ATD_ID': '',
      'H_OTHER_TD': '',
    });
    expect(sections.first, {
      'S_EVENT_ID': 'MEOW',
      'S_SEC_NUM': '1',
      'S_SEC_NAME': 'Section 0',
      // G/60 d/5 is 65 minutes: dual rated under rule 5C.
      'S_R_SYSTEM': 'D',
      'S_TIMECTL': 'Game/60 d/5',
      'S_CTD_ID': '00123456',
      'S_ATD_ID': '',
      'S_TRN_TYPE': 'S',
      'S_TOT_RNDS': '12',
      'S_LST_PAIR': '15',
      'S_BEG_DATE': '20240228',
      'S_END_DATE': '20240229',
      'S_SCH_LVL': 'N',
      'S_GR_PRIX': 'N',
      'S_GP_PTS': '0',
      'S_FIDE': 'N',
    });
    expect(details.take(4).map((d) => (d['D_NAME'], d['D_STATE'])), [
      ('FAMILY0, GIVEN0', 'MA'),
      ('ALVAREZ, JOSE', 'NH'),
      ('FAMILY-SMITH, GIVEN', 'MA'),
      ('FAMILY3, GIVEN3', 'NH'),
    ]);
    expect(details.first['D_RATING'], '0');
    for (final d in details) {
      for (final MapEntry(:key, :value) in d.entries) {
        if (key.startsWith('D_RND')) {
          expect(value, matches(RegExp(r'^([WDL]\d{1,4}[WB]|[XFBHU]0)$')));
        }
      }
    }
  });

  test('H_PROGRAM names the released version and fits ten characters', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(appVersion, version);
    expect('MEOW $appVersion'.length, lessThanOrEqualTo(10));
  });

  test('rating category follows every rule 5C example', () {
    // The TD TIP table in rule 5C, 7th edition, verbatim.
    const examples = {
      '40/90 SD/30 inc/30': RatingCategory.regular,
      '40/120 SD/60 d/5': RatingCategory.regular,
      '40/115 SD/60 d/5': RatingCategory.regular,
      'G/120 inc/30': RatingCategory.regular,
      'G/120 d/5': RatingCategory.regular,
      'G/115 d/5': RatingCategory.regular,
      'G/90 inc/30': RatingCategory.regular,
      'G/90 d/5': RatingCategory.regular,
      'G/60 inc/30': RatingCategory.regular,
      'G/60 d/5': RatingCategory.dual,
      '30/30 SD/30 d/5': RatingCategory.dual,
      'G/30 d/5': RatingCategory.dual,
      'G/25 d/5': RatingCategory.dual,
      'G/25 d/3': RatingCategory.quick,
      'G/15 d/3': RatingCategory.quick,
      'G/10 d/3': RatingCategory.quick,
      'G/10 d/0': RatingCategory.blitz,
      'G/5 d/0': RatingCategory.blitz,
      'G/3 inc/2': RatingCategory.blitz,
      // Notes 1 and 2 under rule 5C.
      'G/61 d/5': RatingCategory.regular,
      'G/26 d/3': RatingCategory.quick,
      // Boundaries.
      'G/66': RatingCategory.regular,
      'G/65': RatingCategory.dual,
      'G/30': RatingCategory.dual,
      'G/29': RatingCategory.quick,
      'G/11': RatingCategory.quick,
      'G/10': RatingCategory.blitz,
      'G/5': RatingCategory.blitz,
    };
    for (final MapEntry(:key, :value) in examples.entries) {
      expect(TimeControl.parse(key).category, value, reason: key);
    }
    for (final unratable in ['G/4', 'G/2 inc/2', 'G/4 inc/10', '40/2, SD/1']) {
      expect(TimeControl.parse(unratable).category, isNull, reason: unratable);
    }
    expect(RatingCategory.blitz.code, isNull);
    expect(RatingCategory.values.map((c) => c.code).whereType<String>(), [
      'R',
      'D',
      'Q',
    ]);
  });

  test('time controls in common notations become the 2C form', () {
    const forms = {
      'G/60 d/5': 'Game/60 d/5',
      'G/60;d5': 'Game/60 d/5',
      'g/60 d5': 'Game/60 d/5',
      'Game/45': 'Game/45',
      'G45': 'Game/45',
      'G/90+30': 'Game/90 inc/30',
      'G/90;+30': 'Game/90 inc/30',
      'G/90 inc30': 'Game/90 inc/30',
      'G/90 inc/30 sec': 'Game/90 inc/30',
      'G/65 d10': 'Game/65 d/10',
      '40/90, SD/30': '40/90, SD/30',
      '40/90,SD/30;inc30': '40/90, SD/30 inc/30',
      '40/120, 20/60, SD/30 d/5': '40/120, 20/60, SD/30 d/5',
      '40/120 G/30 d10': '40/120, SD/30 d/10',
    };
    for (final MapEntry(:key, :value) in forms.entries) {
      expect(TimeControl.parse(key).reportText, value, reason: key);
    }
    for (final invalid in [
      '',
      'banana',
      '60 minutes',
      'G/60 d/5 inc/5',
      'd/5 G/60',
      'G/60 G/30',
      '40/90',
      'G/0',
      'G/60 d/5 extra',
      'G/60d5',
      'G/1000',
    ]) {
      expect(
        () => TimeControl.parse(invalid),
        throwsA(isA<TournamentException>()),
        reason: invalid,
      );
    }
  });

  test('player names become LAST, FIRST in plain capitals', () {
    const names = {
      'John Smith': 'SMITH, JOHN',
      'Smith, John': 'SMITH, JOHN',
      'smith,john': 'SMITH, JOHN',
      '  Mary   Ann  Lee ': 'LEE, MARY ANN',
      'John Smith Jr.': 'SMITH, JOHN JR.',
      'John Smith, Jr.': 'SMITH, JOHN JR.',
      'Juan de la Cruz': 'DE LA CRUZ, JUAN',
      'Ludwig van Beethoven': 'VAN BEETHOVEN, LUDWIG',
      'Mary St. John': 'ST. JOHN, MARY',
      'José Álvarez': 'ALVAREZ, JOSE',
      'Zoë Ødegård': 'ODEGARD, ZOE',
      'Łukasz Żmuda': 'ZMUDA, LUKASZ',
      'Grüße Straße': 'STRASSE, GRUSSE',
      'Sébastien Roy': 'ROY, SEBASTIEN',
      'Patrick O’Brien': "O'BRIEN, PATRICK",
      'Anne-Marie Dubois': 'DUBOIS, ANNE-MARIE',
      'Madonna': 'MADONNA',
      'Smith,': 'SMITH',
    };
    for (final MapEntry(:key, :value) in names.entries) {
      expect(reportName(key), value, reason: key);
      expect(reportNameProblem(value), isNull, reason: key);
    }
    expect(reportName('李 小龙'), isNull);
    expect(reportName('   '), isNull);
    expect(reportNameProblem('A' * 31), contains('30'));
    expect(reportNameProblem('SMITH; JOHN'), isNotNull);
    expect(
      playerReportName(
        Player(id: 'x', name: '李 小龙', reportName: 'Li, Xiaolong'),
      ),
      'LI, XIAOLONG',
    );
  });

  test('every blocking problem is reported before any file is written', () {
    final event = exportFixture();
    Event section0(Section Function(Section) change) => event.copy(
      sections: [change(event.sections.first), event.sections.last],
    );
    final cases = <String, (Event, String)>{
      'practice': (event.copy(practice: true), 'Practice'),
      'no TD': (event.copy(tdId: ''), 'chief TD'),
      'placeholder TD': (event.copy(tdId: '00000000'), 'chief TD'),
      'short TD': (event.copy(tdId: '1234567'), 'chief TD'),
      'numeric affiliate': (event.copy(affiliateId: '87654321'), 'affiliate'),
      'lowercase affiliate': (event.copy(affiliateId: 'a6012345'), 'affiliate'),
      'long name': (event.copy(name: 'x' * 36), 'Event name'),
      'quote in name': (event.copy(name: 'The "Big" Open'), 'Event name'),
      'unspellable name': (event.copy(name: '東京 Open'), 'Event name'),
      'future end': (event.copy(endDate: '2024-03-16'), 'after today'),
      'future start': (
        event.copy(date: '2024-04-01', endDate: ''),
        'after today',
      ),
      'end before start': (event.copy(date: '2024-03-01'), 'last day'),
      'invalid end': (event.copy(endDate: '2024-02-30'), 'last day'),
      'ancient date': (event.copy(date: '1899-12-31'), 'event date'),
      'no city': (event.copy(city: ''), 'City'),
      'long city': (event.copy(city: 'x' * 22), 'City'),
      'bad event state': (event.copy(state: 'XX'), 'state where'),
      'lowercase event state': (event.copy(state: 'ma'), 'state where'),
      'bad ZIP': (event.copy(zip: '0211'), 'ZIP'),
      'zero ZIP': (event.copy(zip: '00000'), 'ZIP'),
      'bad level': (event.copy(level: 'X'), 'event type'),
      'blitz': (event.copy(timeControl: 'G/5 d/0'), 'Blitz'),
      'unratable': (event.copy(timeControl: 'G/3'), 'not ratable'),
      'unparseable': (event.copy(timeControl: 'Game in 60'), 'Time control'),
      'long section': (section0((s) => s.copy(name: 'x' * 31)), 'Section name'),
      'double games': (section0((s) => s.copy(doubleGames: true)), 'Double'),
      'unfinished': (
        section0((s) => s.copy(rounds: s.rounds.take(11).toList())),
        'Complete all',
      ),
      'no ID': (
        withPlayer(event, 0, (p) => p.copy(memberId: '')),
        'ID missing',
      ),
      'placeholder ID': (
        withPlayer(event, 0, (p) => p.copy(memberId: '00000000')),
        'ID missing',
      ),
      'shared ID': (
        withPlayer(
          event,
          20,
          (p) => p.copy(memberId: event.players[3].memberId),
        ),
        'is entered for',
      ),
      'no state': (
        withPlayer(event, 4, (p) => p.copy(state: '')),
        'State missing',
      ),
      'unspellable player': (
        withPlayer(event, 5, (p) => p.copy(name: '李 小龙')),
        'Name on rating report',
      ),
      'long player name': (
        withPlayer(event, 5, (p) => p.copy(reportName: 'x' * 31)),
        'Name on rating report',
      ),
      'stray bye': (
        section0(
          (s) => s.copy(
            rounds: [
              for (final r in s.rounds)
                r.number == 1
                    ? r.copy(byes: [...r.byes, const ByeAward('p29', 0, 'x')])
                    : r,
            ],
          ),
        ),
        'no longer in the section',
      ),
    };
    for (final MapEntry(key: label, value: (invalid, message))
        in cases.entries) {
      final issues = ratingPreflight(invalid, today: today);
      expect(issues.join('\n'), contains(message), reason: label);
      expect(
        () => ratingPackage(invalid, today: today),
        throwsA(isA<TournamentException>()),
        reason: label,
      );
    }
    for (final outcome in [
      Outcome.unreported,
      Outcome.unfinished,
      Outcome.disputed,
    ]) {
      final invalid = section0(
        (s) => s.copy(
          rounds: [
            ...s.rounds.take(11),
            s.rounds.last.copy(
              games: [
                s.rounds.last.games.first.copy(outcome: outcome),
                ...s.rounds.last.games.skip(1),
              ],
            ),
          ],
        ),
      );
      expect(
        ratingPreflight(invalid, today: today),
        contains('Complete all scheduled rounds and results.'),
      );
    }
  });

  test('a section of only forfeits and byes is not reported', () {
    final event = exportFixture();
    Section forfeitOnly(Section s) => s.copy(
      rounds: [
        for (final r in s.rounds)
          r.copy(
            games: [
              for (final g in r.games) g.copy(outcome: Outcome.whiteForfeit),
            ],
          ),
      ],
    );
    expect(
      ratingPreflight(
        event.copy(
          sections: [forfeitOnly(event.sections.first), event.sections.last],
        ),
        today: today,
      ),
      contains('Section Section 0 has no played games to rate.'),
    );
  });

  test('accepted inputs in other spellings are exported the same way', () {
    final base = ratingPackage(exportFixture(), today: today);
    final alternate = ratingPackage(
      exportFixture().copy(timeControl: 'g/60 d5', endDate: '2024-02-29'),
      today: today,
    );
    expect(alternate, base);
    final oneDay = readDbf(
      ratingPackage(
        exportFixture().copy(endDate: ''),
        today: today,
      )['THEXPORT.DBF']!,
    ).$2.single;
    expect(oneDay['H_END_DATE'], '20240228');
  });

  test('events saved before report fields existed still load', () {
    final json = exportFixture().toJson();
    for (final key in ['endDate', 'city', 'state', 'zip', 'level']) {
      json.remove(key);
    }
    for (final p in json['players'] as List) {
      (p as Map)
        ..remove('state')
        ..remove('reportName');
    }
    final old = Event.fromJson(jsonDecode(jsonEncode(json)));
    validateEvent(old);
    expect(
      (old.endDate, old.city, old.state, old.zip, old.level),
      ('', '', '', '', 'N'),
    );
    expect(old.players.first.state, '');
    final fresh = exportFixture();
    expect(Event.decode(fresh.encode()).encode(), fresh.encode());
    expect(
      () => validateEvent(fresh.copy(endDate: '2024-02-27')),
      throwsA(isA<TournamentException>()),
    );
    expect(
      () => validateEvent(withPlayer(fresh, 0, (p) => p.copy(state: 'ma'))),
      throwsA(isA<TournamentException>()),
    );
  });

  test('concurrent exports publish separate complete packages', () async {
    final folder = Directory.systemTemp.createTempSync(
      'meow concurrent exports ',
    );
    addTearDown(() => folder.deleteSync(recursive: true));
    final event = exportFixture();
    final paths = await Future.wait([
      for (var i = 0; i < 8; i++)
        writeRatingPackage(event.copy(revision: i), folder.path),
    ]);
    expect(paths.toSet(), hasLength(8));
    for (final (i, path) in paths.indexed) {
      expect(Directory(path).listSync(), hasLength(4));
      final manifest =
          jsonDecode(File(p.join(path, 'manifest.json')).readAsStringSync())
              as Map;
      expect(manifest['revision'], i);
      expect(manifest['ratingSystem'], 'D');
      for (final entry in ratingPackage(event).entries) {
        expect(File(p.join(path, entry.key)).readAsBytesSync(), entry.value);
      }
    }
    expect(
      folder.listSync().any((f) => p.basename(f.path).startsWith('.')),
      false,
    );
  });

  test(
    'publishing a package preserves previous files and records exact revision',
    () async {
      final folder = Directory.systemTemp.createTempSync('meow export é ');
      addTearDown(() => folder.deleteSync(recursive: true));
      final event = exportFixture();
      final first = await writeRatingPackage(event, folder.path);
      final bytes = File(p.join(first, 'TDEXPORT.DBF')).readAsBytesSync();
      final second = await writeRatingPackage(
        event.copy(revision: 7),
        folder.path,
      );
      expect(first, isNot(second));
      expect(File(p.join(first, 'TDEXPORT.DBF')).readAsBytesSync(), bytes);
      final manifest =
          jsonDecode(File(p.join(second, 'manifest.json')).readAsStringSync())
              as Map;
      expect(manifest['revision'], 7);
      expect(manifest['eventId'], event.id);
      for (final entry in (manifest['files'] as Map).entries) {
        expect(
          File(p.join(second, entry.key as String)).lengthSync(),
          entry.value,
        );
      }
      expect(folder.listSync().any((f) => f.path.endsWith('.partial')), false);
      await expectLater(
        writeRatingPackage(event.copy(practice: true), folder.path),
        throwsA(isA<TournamentException>()),
      );
      expect(folder.listSync(), hasLength(2));
      final obstruction = File(p.join(folder.path, 'ordinary file'))
        ..writeAsStringSync('preserve');
      await expectLater(
        writeRatingPackage(event, obstruction.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(obstruction.readAsStringSync(), 'preserve');
    },
  );
}
