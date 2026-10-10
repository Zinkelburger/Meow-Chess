import 'fide_pairing.dart';
import 'model.dart';
import 'pairing.dart';
import 'standings.dart';
import 'trf_read.dart';

/// The Pairings and Tie-Breaks Checker (PTC) the FIDE Technical Commission
/// asks of a tournament program (C.02.03 7.2.3; TEC Manual 3.9.4.2c): it
/// reads a TRF, rebuilds the tournament round by round, pairs each round
/// with the program's own engine and ranks the final standings by the
/// file's tie-breaks, and reports where the file differs.

/// One difference between the file and what Meow-Chess computes.
class FideCheckIssue {
  const FideCheckIssue(this.round, this.message);

  /// The round re-paired, or 0 for the standings.
  final int round;
  final String message;
  @override
  String toString() =>
      round == 0 ? 'Standings: $message' : 'Round $round: $message';
}

/// What a check found. [inputs] holds the engine input (ITDX TRF) for
/// each round, when asked for.
class FideCheckReport {
  FideCheckReport(this.file, this.issues, this.notes, this.inputs);
  final TrfFile file;
  final List<FideCheckIssue> issues;

  /// What was not checked, and why; import notes.
  final List<String> notes;
  final Map<int, String> inputs;

  bool get ok => issues.isEmpty;

  /// A plain-text report, one line per finding.
  String get text {
    final rounds = file.playedRounds;
    return [
      'Tournament: ${file.name.isEmpty ? '(no name)' : file.name}',
      'Players: ${file.players.length}, rounds held: $rounds',
      for (final n in notes) 'Note: $n',
      if (ok) 'OK: every pairing and the standings match.',
      for (final i in issues) i.toString(),
    ].join('\n');
  }
}

/// Checks the TRF [text]. [rounds] limits the pairing check to those
/// rounds (all by default); [pairings] and [ranking] choose the parts to
/// check. With [keepInputs] the report carries each round's engine input.
FideCheckReport checkTrf(
  String text, {
  Set<int>? rounds,
  bool pairings = true,
  bool ranking = true,
  bool keepInputs = false,
}) {
  final file = TrfFile.parse(text);
  var ids = 0;
  final imported = trfToEvent(
    file,
    newId: () => 'x${++ids}',
    today: '2026-01-01',
  );
  final event = imported.event;
  final section = event.sections.single;
  final issues = <FideCheckIssue>[];
  final notes = [...imported.warnings];
  final inputs = <int, String>{};
  final rankOf = {for (final (i, id) in section.fideOrder.indexed) id: i + 1};
  String nameOf(String id) => '${rankOf[id]}';

  if (pairings && section.format != Format.swiss) {
    notes.add('Pairings were not checked: the file is not a Swiss.');
  } else if (pairings) {
    for (var n = 1; n <= section.rounds.length; n++) {
      if (rounds != null && !rounds.contains(n)) continue;
      final actual = section.rounds[n - 1];
      // Who the file shows as not paired in round n (absent, or a
      // requested bye) sits out; the pairing-allocated bye is the
      // engine's to give.
      final out = {
        for (final b in actual.byes)
          if (!b.allocated) b.player: b.points,
      };
      var base = event.copy(
        players: [
          for (final p in event.players)
            p.copy(
              byes: {if (out.containsKey(p.id)) n: out[p.id]!},
              withdrawn: false,
            ),
        ],
        sections: [section.copy(rounds: section.rounds.take(n - 1).toList())],
      );
      if (n == 1) base = _rankedByPairingNumber(base, rankOf);
      final s = base.sections.single;
      if (keepInputs) {
        final (_, byes) = roundAvailability(base, s, n);
        inputs[n] = fideEngineInput(base, s, n, byes);
      }
      final Round paired;
      try {
        paired = proposeRound(base, s, () => 'check');
      } on TournamentException catch (e) {
        issues.add(
          FideCheckIssue(n, 'the engine could not pair it: ${e.message}'),
        );
        continue;
      }
      String pair(Game g) => '${nameOf(g.white)}-${nameOf(g.black)}';
      final expected = {for (final g in paired.games) pair(g)};
      final found = {for (final g in actual.games) pair(g)};
      final expectedBye = paired.byes.where((b) => b.allocated);
      final foundBye = actual.byes.where((b) => b.allocated);
      final missing = expected.difference(found).toList()..sort(_byNumbers);
      final extra = found.difference(expected).toList()..sort(_byNumbers);
      if (missing.isNotEmpty || extra.isNotEmpty) {
        issues.add(
          FideCheckIssue(
            n,
            'the engine pairs ${missing.join(', ')}; the file has ${extra.join(', ')}.',
          ),
        );
      }
      final eb = expectedBye.map((b) => nameOf(b.player)).join();
      final fb = foundBye.map((b) => nameOf(b.player)).join();
      if (eb != fb) {
        issues.add(
          FideCheckIssue(
            n,
            'the pairing-allocated bye goes to ${eb.isEmpty ? 'nobody' : eb}; the file gives it to ${fb.isEmpty ? 'nobody' : fb}.',
          ),
        );
      }
    }
  }

  if (ranking) {
    final records = {for (final r in file.players) r.rank: r};
    // Without listed tie-breaks only points order the file; players on the
    // same points may stand in any order.
    final rows = standings(
      event,
      section,
      tiebreaks: event.fideTiebreaks.isEmpty ? const [] : null,
    );
    if (event.fideTiebreaks.isEmpty) {
      notes.add(
        'The file lists no tie-breaks (record 202 or 212), so only points and shared places were checked.',
      );
    }
    // Places: Meow-Chess lets players still tied after every tie-break
    // share a place; the file may break those ties by lot.
    final groups = <int, List<Standing>>{};
    for (final row in rows) {
      (groups[row.rank] ??= []).add(row);
    }
    for (final row in rows) {
      final r = records[rankOf[row.player.id]]!;
      if (r.points != null && r.points != row.points) {
        issues.add(
          FideCheckIssue(
            0,
            'player ${r.rank} has ${_points(row.points)} points; the file says ${_points(r.points!)}.',
          ),
        );
      }
      if (r.place == 0) continue;
      final shared = groups[row.rank]!.length;
      final low = row.rank, high = row.rank + shared - 1;
      if (r.place < low || r.place > high) {
        issues.add(
          FideCheckIssue(
            0,
            'player ${r.rank} ranks ${shared > 1 ? '$low–$high (tied)' : '$low'}; the file says ${r.place}.',
          ),
        );
      }
    }
  }
  return FideCheckReport(file, issues, notes, inputs);
}

/// [event] with every player's ranking data replaced so that C.04.2's
/// initial order is exactly [rankOf]: no ratings or titles, and names
/// that sort by pairing number. The Dutch system pairs by pairing number,
/// so this only fixes the order of round 1.
Event _rankedByPairingNumber(Event event, Map<String, int> rankOf) =>
    event.copy(
      players: [
        for (final p in event.players)
          p.copy(
            name: 'P${'${rankOf[p.id] ?? 9999}'.padLeft(4, '0')}',
            fideStandard: 0,
            fideRapid: 0,
            fideBlitz: 0,
            rating: 0,
            pairingRating: 0,
            title: '',
          ),
      ],
      sections: [
        for (final s in event.sections)
          s.copy(fideOrder: const [], fideRanking: 'FIDE'),
      ],
    );

int _byNumbers(String a, String b) {
  int first(String x) => int.parse(x.split('-').first);
  return first(a).compareTo(first(b));
}

String _points(int halves) => '${halves ~/ 2}${halves.isOdd ? '.5' : '.0'}';
