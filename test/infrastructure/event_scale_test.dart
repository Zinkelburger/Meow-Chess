import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;

/// A large open: 300 players, one Swiss section, five rounds, every result
/// entered one at a time. The numbers are printed so a slower commit or a
/// fatter file shows up in the test log before a director meets it.
void main() {
  test('a 300-player, 5-round Swiss saves quickly and stays small', () async {
    final directory = Directory.systemTemp.createTempSync('meow-scale-');
    addTearDown(() => directory.deleteSync(recursive: true));
    // Reading every save back, as tests do, is not part of what a director
    // waits for.
    SqliteEventRepository.debugVerifyWrites = false;
    addTearDown(() => SqliteEventRepository.debugVerifyWrites = true);
    final path = p.join(directory.path, 'open.meow');
    final c = TournamentController(SqliteEventRepository(path));
    addTearDown(c.dispose);
    c.create('State Open');
    c.importPlayers([
      for (var i = 0; i < 300; i++)
        Player(
          id: 'p$i',
          name: 'Player Number ${i.toString().padLeft(3, '0')}, Jr.',
          rating: 2400 - i * 5,
          memberId: '${12000000 + i}',
          club: 'Club ${i % 12}',
          state: 'MA',
        ),
    ]);
    c.addSection('Open', Format.swiss, 5);
    final sectionId = c.event!.sections.single.id;
    final commits = <int>[];
    final clock = Stopwatch();
    for (var round = 1; round <= 5; round++) {
      c.post(await c.propose(sectionId: sectionId));
      final games = c.event!.sections.single.rounds.last.games;
      for (final (i, game) in games.indexed) {
        clock
          ..reset()
          ..start();
        c.recordResult(
          game.id,
          const [Outcome.whiteWin, Outcome.draw, Outcome.blackWin][i % 3],
        );
        commits.add(clock.elapsedMicroseconds);
      }
    }
    commits.sort();
    double ms(int micros) => micros / 1000;
    final median = ms(commits[commits.length ~/ 2]);
    final p95 = ms(commits[commits.length * 95 ~/ 100]);
    final megabytes = File(path).lengthSync() / (1024 * 1024);
    clock
      ..reset()
      ..start();
    c.repository.backup(p.join(directory.path, 'copy.meow'));
    final backup = clock.elapsedMilliseconds;
    final wal = File('$path-wal');
    // ignore: avoid_print
    print(
      'SCALE: ${commits.length} results; commit median '
      '${median.toStringAsFixed(1)} ms, p95 ${p95.toStringAsFixed(1)} ms, '
      'slowest ${ms(commits.last).toStringAsFixed(1)} ms; file '
      '${megabytes.toStringAsFixed(1)} MB after '
      '${c.repository.history().length} saves; full copy $backup ms; '
      'recovery file ${wal.existsSync() ? wal.lengthSync() : 0} bytes',
    );
    expect(c.event!.sections.single.rounds, hasLength(5));
    expect(c.event!.games.every((g) => g.outcome.resolved), isTrue);
    // Generous bounds for a shared test machine; the printed figures are
    // the ones to compare between changes.
    expect(median, lessThan(100));
    expect(megabytes, lessThan(40));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
