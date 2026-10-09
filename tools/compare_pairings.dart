// Compares the Swiss engine's proposal for every posted round of saved
// events with the pairings those events actually used (for example the
// Boylston archive replays under artifacts/). Differences are not defects by
// themselves: SwissSys variants and TD adjustments both produce legal
// pairings. The report lists each differing board with scores, ratings and
// the engine's explanations so a director can judge them.
//
//   dart run tools/compare_pairings.dart artifacts/<run>/*.meow
import 'dart:io';

import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

void main(List<String> args) {
  var boards = 0, sameOpponents = 0, sameColors = 0, byes = 0, sameByes = 0;
  var rounds = 0, identicalRounds = 0;
  for (final path in args) {
    final repository = SqliteEventRepository(path);
    final Event event;
    try {
      event = repository.load() ?? (throw StateError('$path has no event'));
    } finally {
      repository.close();
    }
    stdout.writeln('=== ${event.name} ($path)');
    for (final section in event.sections) {
      if (section.sideGames || pairingFormat(section) != Format.swiss) {
        continue;
      }
      for (var r = 1; r <= section.rounds.length; r++) {
        final actual = section.rounds[r - 1];
        if (actual.games.isEmpty) continue;
        final result = _compare(event, section, r);
        if (result == null) continue;
        rounds++;
        boards += result.boards;
        sameOpponents += result.sameOpponents;
        sameColors += result.sameColors;
        byes += result.byes;
        sameByes += result.sameByes;
        if (result.sameOpponents == result.boards &&
            result.sameByes == result.byes) {
          identicalRounds++;
        }
        stdout.writeln(
          '--- ${section.name} round $r: ${result.sameOpponents}/${result.boards} boards, '
          '${result.sameColors}/${result.sameOpponents} colors, '
          '${result.sameByes}/${result.byes} byes',
        );
        for (final line in result.lines) {
          stdout.writeln('    $line');
        }
      }
    }
  }
  stdout.writeln();
  stdout.writeln(
    'TOTAL: $identicalRounds/$rounds rounds identical; $sameOpponents/$boards boards same opponents; '
    '$sameColors/$sameOpponents of those same colors; $sameByes/$byes byes same',
  );
}

class _Result {
  int boards = 0, sameOpponents = 0, sameColors = 0, byes = 0, sameByes = 0;
  final lines = <String>[];
}

_Result? _compare(Event event, Section section, int r) {
  final actual = section.rounds[r - 1];
  final inRound = <String>{
    for (final g in actual.games) ...[g.white, g.black],
  };
  // Who the engine should consider: requested byes become reservations,
  // absentees are withdrawn for this proposal, and the allocated bye is
  // the engine's to choose.
  final requested = <String, int>{};
  for (final b in actual.byes) {
    if (!b.allocated && !event.player(b.player).withdrawn) {
      requested[b.player] = b.points.clamp(0, 2);
    }
    if (b.allocated) inRound.add(b.player);
  }
  final players = [
    for (final p in event.players)
      if (requested.containsKey(p.id))
        p.copy(byes: {r: requested[p.id]!}, withdrawn: false)
      else if (inRound.contains(p.id))
        p.copy(withdrawn: false, byes: const {})
      else
        p.copy(withdrawn: true, byes: const {}),
  ];
  final truncated = event.copy(
    players: players,
    sections: [
      for (final s in event.sections)
        s.copy(
          rounds: s.id == section.id
              ? s.rounds.take(r - 1).toList()
              : s.rounds.where((x) => x.number < r).toList(),
        ),
    ],
  );
  final target = truncated.sections.firstWhere((s) => s.id == section.id);
  final Round proposed;
  try {
    var n = 0;
    proposed = proposeRound(truncated, target, () => 'cmp${n++}');
  } on TournamentException catch (e) {
    final out = _Result();
    out.lines.add('ENGINE REFUSED: ${e.message}');
    return out;
  }
  final out = _Result();
  final scores = {
    for (final row in standings(truncated, target, forPairing: true))
      row.player.id: row.points,
  };
  String who(String id) {
    final p = event.player(id);
    return '${p.name} (${scoreText(scores[id] ?? 0)}, ${p.rating == 0 ? 'UNR' : p.rating})';
  }

  String key(String a, String b) => ([a, b]..sort()).join('|');
  final proposedPairs = {
    for (final g in proposed.games.where((g) => g.leg == 1))
      key(g.white, g.black): g,
  };
  final actualLeg1 = actual.games.where((g) => g.leg == 1).toList();
  out.boards = actualLeg1.length;
  final missing = <Game>[];
  for (final g in actualLeg1) {
    final p = proposedPairs[key(g.white, g.black)];
    if (p == null) {
      missing.add(g);
      continue;
    }
    out.sameOpponents++;
    if (p.white == g.white) out.sameColors++;
  }
  final actualBye = actual.byes.where((b) => b.allocated).map((b) => b.player);
  final proposedBye = proposed.byes
      .where((b) => b.allocated)
      .map((b) => b.player)
      .toSet();
  out.byes = actualBye.length;
  for (final id in actualBye) {
    if (proposedBye.contains(id)) {
      out.sameByes++;
    } else {
      out.lines.add(
        'bye: actual ${who(id)}; engine ${proposedBye.isEmpty ? 'none' : proposedBye.map(who).join(', ')}',
      );
    }
  }
  if (missing.isNotEmpty) {
    final actualKeys = {for (final g in actualLeg1) key(g.white, g.black)};
    out.lines.add('actual boards the engine paired differently:');
    for (final g in missing) {
      out.lines.add('  ${who(g.white)} - ${who(g.black)}');
    }
    out.lines.add('engine instead:');
    for (final g in proposed.games.where(
      (g) => g.leg == 1 && !actualKeys.contains(key(g.white, g.black)),
    )) {
      out.lines.add('  ${who(g.white)} - ${who(g.black)}');
    }
    for (final line in proposed.explanations) {
      out.lines.add('  · $line');
    }
  }
  return out;
}
