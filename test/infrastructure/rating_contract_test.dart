import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:path/path.dart' as p;

const metadata = ReportMetadata(
  city: 'Boston', state: 'MA', zip: '02116-1234', ratingSystem: 'R',
);

// A serialization fixture, not a claim that these results form a rated event.
// Two sections exercise section-local pairing numbers; 12 rounds catch the
// obsolete ten-round/pointer DBF layout; every outcome and bye code is present.
Event exportFixture() {
  final players = [
    for (var i = 0; i < 30; i++)
      Player(id: 'p$i', name: 'Player $i', memberId: '${123456 + i}'.padLeft(8, '0'), rating: i == 0 ? 0 : 1800 - i * 10),
  ];
  final sections = [
    for (var s = 0; s < 2; s++)
      Section(
        id: 's$s', name: 'Section $s', plannedRounds: 12,
        players: players.skip(s * 15).take(15).map((p) => p.id).toList(),
        boardStart: 1 + s * 8,
        rounds: [
          for (final (r, pairs) in roundRobinSchedule(players.skip(s * 15).take(15).map((p) => p.id).toList()).take(12).indexed)
            Round(number: r + 1, games: [
              for (final (b, pair) in pairs.indexed)
                if (pair.$1 != null && pair.$2 != null)
                  Game(id: '$s-$r-$b', white: pair.$1!, black: pair.$2!, board: 1 + s * 8 + b,
                    outcome: const [Outcome.whiteWin, Outcome.draw, Outcome.blackWin, Outcome.whiteForfeit, Outcome.blackForfeit, Outcome.doubleForfeit][(b + r) % 6]),
            ], byes: [
              for (final pair in pairs)
                if (pair.$1 == null || pair.$2 == null)
                  ByeAward((pair.$1 ?? pair.$2)!, r % 3, 'Fixture bye', allocated: r % 3 == 2),
            ]),
        ],
      ),
  ];
  return Event(id: 'export-contract', name: 'Synthetic export contract', date: '2024-02-29', tdId: '00123456', affiliateId: '00876543', players: players, sections: sections);
}

void main() {
  test('2C package covers all outcomes, byes, sections and round 12', () {
    final event = exportFixture();
    validateEvent(event);
    final files = ratingPackage(event, metadata);
    expect(files.keys, unorderedEquals(['THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF']));
    expect(event.games.map((g) => g.outcome).toSet(), hasLength(6));
    if (Platform.environment['MEOW_EXPORT_FIXTURES'] == '1') {
      final folder = Directory('artifacts/dbf-contract')..createSync(recursive: true);
      for (final file in files.entries) {
        File(p.join(folder.path, file.key)).writeAsBytesSync(file.value);
      }
      File(p.join(folder.path, 'expected-event.json')).writeAsStringSync(event.encode());
    }
  });

  test('unsafe and unsupported rating exports fail closed', () {
    final event = exportFixture();
    for (final invalid in [
      event.copy(practice: true),
      event.copy(tdId: ''),
      event.copy(affiliateId: 'bad'),
      event.copy(players: [event.players.first.copy(memberId: ''), ...event.players.skip(1)]),
      event.copy(players: [event.players.first.copy(name: 'José'), ...event.players.skip(1)]),
      event.copy(name: 'x' * 36),
      event.copy(sections: [event.sections.first.copy(doubleGames: true), event.sections.last]),
      event.copy(sections: [event.sections.first.copy(rounds: event.sections.first.rounds.take(11).toList()), event.sections.last]),
    ]) {
      expect(() => ratingPackage(invalid, metadata), throwsA(isA<TournamentException>()));
    }
    for (final system in ['B', 'OR', 'OB', 'unknown']) {
      expect(() => ratingPackage(event, ReportMetadata(city: 'Boston', state: 'MA', zip: '02116', ratingSystem: system)), throwsA(isA<TournamentException>()));
    }
    for (final outcome in [Outcome.unreported, Outcome.unfinished, Outcome.disputed]) {
      final section = event.sections.first;
      final round = section.rounds.last;
      final invalid = event.copy(sections: [section.copy(rounds: [...section.rounds.take(11), round.copy(games: [round.games.first.copy(outcome: outcome), ...round.games.skip(1)])]), event.sections.last]);
      expect(() => ratingPackage(invalid, metadata), throwsA(isA<TournamentException>()));
    }
  });

  test('publishing a package preserves previous files and records exact revision', () async {
    final folder = Directory.systemTemp.createTempSync('meow export é ');
    addTearDown(() => folder.deleteSync(recursive: true));
    final event = exportFixture();
    final first = await writeRatingPackage(event, metadata, folder.path);
    final bytes = File(p.join(first, 'TDEXPORT.DBF')).readAsBytesSync();
    final second = await writeRatingPackage(event.copy(revision: 7), metadata, folder.path);
    expect(first, isNot(second));
    expect(File(p.join(first, 'TDEXPORT.DBF')).readAsBytesSync(), bytes);
    final manifest = jsonDecode(File(p.join(second, 'manifest.json')).readAsStringSync()) as Map;
    expect(manifest['revision'], 7);
    expect(manifest['eventId'], event.id);
    for (final entry in (manifest['files'] as Map).entries) {
      expect(File(p.join(second, entry.key as String)).lengthSync(), entry.value);
    }
    expect(folder.listSync().any((f) => f.path.endsWith('.partial')), false);
    await expectLater(writeRatingPackage(event.copy(practice: true), metadata, folder.path), throwsA(isA<TournamentException>()));
    expect(folder.listSync(), hasLength(2));
    final obstruction = File(p.join(folder.path, 'ordinary file'))..writeAsStringSync('preserve');
    await expectLater(writeRatingPackage(event, metadata, obstruction.path), throwsA(isA<FileSystemException>()));
    expect(obstruction.readAsStringSync(), 'preserve');
  });
}
