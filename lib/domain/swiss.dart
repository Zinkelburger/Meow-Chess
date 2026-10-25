import 'dart:convert';
import 'model.dart';

const swissPolicy = 'score-swiss-pilot-v2';

/// Self-contained inputs: later rating, withdrawal and result edits must not
/// silently change the evidence for an already posted pairing.
class SwissEntry {
  SwissEntry({
    required this.id,
    required this.name,
    required this.rating,
    required this.score,
    this.acceleration = 0,
    this.colors = '',
    this.lastFloat = 0,
    this.previousFloat = 0,
    this.byeEligible = true,
    this.halfBye = false,
    this.absent = '',
    this.byePoints = 0,
    Set<String> opponents = const {},
    Set<String> avoid = const {},
  }) : opponents = Set.unmodifiable(opponents),
       avoid = Set.unmodifiable(avoid);
  final String id, name, colors, absent;
  final int rating, score, acceleration, lastFloat, previousFloat, byePoints;
  final bool byeEligible, halfBye;
  final Set<String> opponents, avoid;
  int get pairingScore => score + acceleration;
  int get balance => colors
      .split('')
      .fold(
        0,
        (n, c) =>
            n +
            (c == 'W'
                ? 1
                : c == 'B'
                ? -1
                : 0),
      );
  String get playedColors => colors.replaceAll('-', '');
  String get due => balance > 0
      ? 'B'
      : balance < 0
      ? 'W'
      : playedColors.isEmpty
      ? '-'
      : playedColors.endsWith('W')
      ? 'B'
      : 'W';
  Json toJson() => {
    'id': id,
    'name': name,
    'rating': rating,
    'score': score,
    'acceleration': acceleration,
    'colors': colors,
    'lastFloat': lastFloat,
    'previousFloat': previousFloat,
    'byeEligible': byeEligible,
    'halfBye': halfBye,
    'absent': absent,
    'byePoints': byePoints,
    'opponents': opponents.toList()..sort(),
    'avoid': avoid.toList()..sort(),
  };
  factory SwissEntry.fromJson(Json j) => SwissEntry(
    id: j['id'],
    name: j['name'],
    rating: j['rating'],
    score: j['score'],
    acceleration: j['acceleration'],
    colors: j['colors'],
    lastFloat: j['lastFloat'],
    previousFloat: j['previousFloat'],
    byeEligible: j['byeEligible'],
    halfBye: j['halfBye'],
    absent: j['absent'],
    byePoints: j['byePoints'],
    opponents: Set<String>.from(j['opponents']),
    avoid: Set<String>.from(j['avoid']),
  );
}

class SwissInput {
  SwissInput({
    required this.round,
    required List<SwissEntry> players,
    this.firstColorWhite = true,
    this.byePoints = 2,
    this.doubleGames = false,
  }) : players = List.unmodifiable(players);
  final int round, byePoints;
  final bool firstColorWhite;
  final bool doubleGames;
  final List<SwissEntry> players;
  String encode() => jsonEncode({
    'version': swissPolicy,
    'round': round,
    'firstColorWhite': firstColorWhite,
    'byePoints': byePoints,
    'doubleGames': doubleGames,
    'players': players.map((p) => p.toJson()).toList(),
  });
  factory SwissInput.decode(String source) {
    final j = jsonDecode(source) as Json;
    if (j['version'] != swissPolicy) {
      throw const TournamentException(
        'This saved pairing uses a different engine version.',
      );
    }
    return SwissInput(
      round: j['round'],
      firstColorWhite: j['firstColorWhite'],
      byePoints: j['byePoints'],
      doubleGames: j['doubleGames'] ?? false,
      players: (j['players'] as List)
          .map((p) => SwissEntry.fromJson(p))
          .toList(),
    );
  }
}

SwissInput swissInput(Event e, Section section) {
  final round = section.rounds.length + 1;
  final scores = {for (final p in e.players) p.id: 0};
  final opponents = <String, Set<String>>{};
  final colors = <String, String>{};
  final floats = <String, Map<int, int>>{};
  final ineligible = <String>{}, halfByes = <String>{};
  // Traverse chronological rounds across sections so transfers keep history.
  for (var n = 1; n < round; n++) {
    final prior = Map<String, int>.from(scores);
    final roundColors = <String, String>{};
    for (final s in e.sections) {
      for (final r in s.rounds.where((r) => r.number == n)) {
        for (final b in r.byes) {
          scores[b.player] = scores[b.player]! + b.points;
          if (b.allocated || b.points >= 2) ineligible.add(b.player);
          if (b.points == 1) halfByes.add(b.player);
        }
        for (final g in r.games) {
          final result = !g.outcome.resolved
              ? g.pairingAssumption ?? g.outcome
              : g.outcome;
          scores[g.white] = scores[g.white]! + s.scoring.points(result, true);
          scores[g.black] = scores[g.black]! + s.scoring.points(result, false);
          if (g.outcome == Outcome.whiteForfeit) ineligible.add(g.white);
          if (g.outcome == Outcome.blackForfeit) ineligible.add(g.black);
          if (!result.played) continue;
          opponents.putIfAbsent(g.white, () => {}).add(g.black);
          opponents.putIfAbsent(g.black, () => {}).add(g.white);
          roundColors[g.white] = '${roundColors[g.white] ?? ''}W';
          roundColors[g.black] = '${roundColors[g.black] ?? ''}B';
          if (g.leg == 1) {
            final difference = (prior[g.black]! + s.accelerationFor(g.black, n))
                .compareTo(prior[g.white]! + s.accelerationFor(g.white, n));
            floats.putIfAbsent(g.white, () => {})[n] = difference;
            floats.putIfAbsent(g.black, () => {})[n] = -difference;
          }
        }
      }
    }
    for (final p in e.players) {
      colors[p.id] = '${colors[p.id] ?? ''}${roundColors[p.id] ?? '-'}';
    }
  }
  return SwissInput(
    round: round,
    firstColorWhite: section.firstColorWhite,
    byePoints: section.scoring.bye,
    doubleGames: section.doubleGames,
    players: [
      for (final id in section.players)
        SwissEntry(
          id: id,
          name: e.player(id).name,
          rating: e.player(id).rating,
          score: scores[id]!,
          acceleration: section.accelerationFor(id, round),
          colors: colors[id] ?? '',
          opponents: opponents[id] ?? {},
          avoid: e.player(id).avoid,
          lastFloat: floats[id]?[round - 1] ?? 0,
          previousFloat: floats[id]?[round - 2] ?? 0,
          byeEligible: !ineligible.contains(id),
          halfBye:
              halfByes.contains(id) || e.player(id).byes.values.contains(1),
          absent: e.player(id).withdrawn
              ? 'Withdrawn'
              : e.player(id).byes.containsKey(round)
              ? 'Requested bye'
              : '',
          byePoints: e.player(id).withdrawn ? 0 : e.player(id).byes[round] ?? 0,
        ),
    ],
  );
}

int _rank(SwissEntry a, SwissEntry b) {
  final score = b.pairingScore.compareTo(a.pairingScore);
  final rating = b.rating.compareTo(a.rating);
  return score != 0
      ? score
      : rating != 0
      ? rating
      : a.id.compareTo(b.id);
}

bool _compatible(SwissEntry a, SwissEntry b) =>
    a.id != b.id &&
    !a.opponents.contains(b.id) &&
    !b.opponents.contains(a.id) &&
    !a.avoid.contains(b.id) &&
    !b.avoid.contains(a.id);

/// Equalize, then use the most recent differing colors, then rank. Empty
/// histories use the recorded first-board color and alternate down the boards.
(SwissEntry, SwissEntry) _orient(
  SwissEntry a,
  SwissEntry b,
  SwissInput input,
  int board,
) {
  bool white;
  if (a.balance != b.balance) {
    white = a.balance < b.balance;
  } else {
    bool? choice;
    final length = a.colors.length > b.colors.length
        ? a.colors.length
        : b.colors.length;
    for (var i = length - 1; i >= 0; i--) {
      final ac = i < a.colors.length ? a.colors[i] : '-';
      final bc = i < b.colors.length ? b.colors[i] : '-';
      if (ac == bc) continue;
      choice = ac == 'B' || bc == 'W';
      break;
    }
    if (choice != null) {
      white = choice;
    } else if (a.due != '-') {
      white = _rank(a, b) <= 0 ? a.due == 'W' : b.due != 'W';
    } else {
      white = board.isEven == input.firstColorWhite;
    }
  }
  return white ? (a, b) : (b, a);
}

int _colorCost((SwissEntry, SwissEntry) pair) {
  var cost = 0;
  for (final (p, color, change) in [(pair.$1, 'W', 1), (pair.$2, 'B', -1)]) {
    if (p.playedColors.endsWith('$color$color')) cost += 10000;
    final balance = (p.balance + change).abs();
    if (balance > 2) cost += 10000;
    cost += balance * 100;
    if (p.due != '-' && p.due != color) cost++;
  }
  return cost;
}

class SwissResult {
  SwissResult(this.pairs, this.bye, this.nodes, this.warnings);
  final List<(String, String)> pairs;
  final String? bye;
  final int nodes;
  final List<String> warnings;
}

/// Independent deterministic search, followed by same-score transpositions.
/// This implements selected US Chess priorities, not full rule conformance.
SwissResult pairSwiss(SwissInput input, {int nodeLimit = 100000}) {
  final available = input.players.where((p) => p.absent.isEmpty).toList()
    ..sort(_rank);
  var nodes = 0;
  List<(SwissEntry, SwissEntry)>? search(List<SwissEntry> left) {
    if (left.isEmpty) return [];
    if (++nodes > nodeLimit) {
      throw const TournamentException(
        'Pairing search limit reached. Review the checklist and use manual pairings.',
      );
    }
    final a = left.first;
    final group = left.where((b) => b.pairingScore == a.pairingScore).toList();
    final target = group.length ~/ 2;
    final choices = left.skip(1).where((b) => _compatible(a, b)).toList();
    int floatPenalty(SwissEntry b) {
      final direction = b.pairingScore.compareTo(a.pairingScore);
      if (direction == 0) return 0;
      return (a.lastFloat == direction ? 2 : 0) +
          (b.lastFloat == -direction ? 2 : 0) +
          (a.previousFloat == direction ? 1 : 0) +
          (b.previousFloat == -direction ? 1 : 0);
    }

    choices.sort((b, c) {
      final gap = (a.pairingScore - b.pairingScore).abs().compareTo(
        (a.pairingScore - c.pairingScore).abs(),
      );
      if (gap != 0) return gap;
      final half = (left.indexOf(b) - target).abs().compareTo(
        (left.indexOf(c) - target).abs(),
      );
      // Float history breaks equal-distance choices between score groups.
      final floater = floatPenalty(b).compareTo(floatPenalty(c));
      if (a.pairingScore != b.pairingScore && floater != 0) {
        return floater;
      }
      return half != 0 ? half : _rank(b, c);
    });
    for (final b in choices) {
      final rest = search(
        left.where((p) => p.id != a.id && p.id != b.id).toList(),
      );
      if (rest != null) return [(a, b), ...rest];
    }
    return null;
  }

  List<(SwissEntry, SwissEntry)>? raw;
  SwissEntry? bye;
  if (available.length.isEven) {
    raw = search(available);
  } else {
    final candidates = available.where((p) => p.byeEligible).toList()
      ..sort((a, b) {
        final score = a.pairingScore.compareTo(b.pairingScore);
        if (score != 0) return score;
        if (a.halfBye != b.halfBye) return a.halfBye ? 1 : -1;
        if ((a.rating == 0) != (b.rating == 0)) return a.rating == 0 ? 1 : -1;
        final rating = a.rating.compareTo(b.rating);
        return rating != 0 ? rating : b.id.compareTo(a.id);
      });
    for (final candidate in candidates) {
      raw = search(available.where((p) => p.id != candidate.id).toList());
      if (raw != null) {
        bye = candidate;
        break;
      }
    }
  }
  if (raw == null) {
    throw const TournamentException(
      'No non-repeat pairing satisfies the opponent requests and bye limits. Review the checklist or adjust the sections.',
    );
  }
  var pairs = [for (final (i, p) in raw.indexed) _orient(p.$1, p.$2, input, i)];
  // Improve two boards without changing their score groups. Rule 29E5c uses
  // the smaller of the two rating differences for a transposition. We handle
  // only these local transpositions, not all interchanges/last-round exceptions.
  // Disjoint swaps prevent a sequence of small switches exceeding the limit
  // relative to the original pairing (29E5).
  final switched = <int>{};
  for (var i = 0; i < raw.length; i++) {
    for (var j = i + 1; j < raw.length; j++) {
      if (switched.contains(i) || switched.contains(j)) continue;
      final (a, b) = raw[i];
      final (c, d) = raw[j];
      if ({
                a.pairingScore,
                b.pairingScore,
                c.pairingScore,
                d.pairingScore,
              }.length !=
              1 ||
          !_compatible(a, d) ||
          !_compatible(c, b)) {
        continue;
      }
      final x = _orient(a, d, input, i), y = _orient(c, b, input, j);
      final before = _colorCost(pairs[i]) + _colorCost(pairs[j]);
      final after = _colorCost(x) + _colorCost(y);
      final delta1 = (a.rating - c.rating).abs(),
          delta2 = (b.rating - d.rating).abs();
      final delta = delta1 < delta2 ? delta1 : delta2;
      final anyUnrated = [a, b, c, d].any((p) => p.rating == 0);
      final limit = after ~/ 100 < before ~/ 100 ? 200 : 80;
      if (after < before && (anyUnrated || delta <= limit)) {
        raw[i] = (a, d);
        raw[j] = (c, b);
        pairs[i] = x;
        pairs[j] = y;
        switched.addAll([i, j]);
      }
    }
  }
  final warnings = <String>[];
  for (final pair in pairs) {
    for (final (p, color, delta) in [(pair.$1, 'W', 1), (pair.$2, 'B', -1)]) {
      if (p.playedColors.endsWith('$color$color')) {
        warnings.add(
          '${p.name}: third consecutive $color; TD review required.',
        );
      }
      if ((p.balance + delta).abs() > 2) {
        warnings.add(
          '${p.name}: color imbalance exceeds two; TD review required.',
        );
      }
    }
  }
  if (bye?.halfBye == true) {
    warnings.add(
      '${bye!.name}: allocated bye after a taken or requested half-point bye; review rule 28L4.',
    );
  }
  if (bye?.rating == 0) {
    warnings.add(
      '${bye!.name}: unrated player receives the bye; review alternatives.',
    );
  }
  return SwissResult(
    [for (final p in pairs) (p.$1.id, p.$2.id)],
    bye?.id,
    nodes,
    warnings,
  );
}

/// Reports deviations from the saved engine decision, not federation approval.
List<String> recheckPairing(Round round) {
  if (round.pairingInput.isEmpty) {
    return [
      'No saved inputs: this round predates pairing checklists or uses a fixed schedule.',
    ];
  }
  final input = SwissInput.decode(round.pairingInput);
  final expected = pairSwiss(input);
  String key(String w, String b, int leg) => jsonEncode([w, b, leg]);
  final actual = round.games.map((g) => key(g.white, g.black, g.leg)).toSet();
  final wanted = {
    for (final p in expected.pairs) ...[
      key(p.$1, p.$2, 1),
      if (input.doubleGames) key(p.$2, p.$1, 2),
    ],
  };
  final issues = <String>[];
  if (round.policy != swissPolicy || round.number != input.round) {
    issues.add('Round number or engine version differs from the saved inputs.');
  }
  if (actual.length != round.games.length ||
      !actual.containsAll(wanted) ||
      !wanted.containsAll(actual)) {
    issues.add(
      'Opponents or colors differ from the saved engine proposal (possibly a manual edit).',
    );
  }
  final expectedByes = <String, int>{
    for (final p in input.players.where((p) => p.absent.isNotEmpty))
      p.id: p.byePoints,
    if (expected.bye != null) expected.bye!: input.byePoints,
  };
  if (round.byes.length != expectedByes.length ||
      round.byes.any(
        (b) =>
            expectedByes[b.player] != b.points ||
            b.allocated != (b.player == expected.bye),
      )) {
    issues.add('Bye assignments differ from the saved engine proposal.');
  }
  return [...issues, ...expected.warnings];
}

String pairingChecklist(Event event, {String? sectionId}) {
  final out = StringBuffer(
    'PAIRING CHECKLIST — ${event.name}\nRevision ${event.revision}\n'
    'Saved inputs at posting time; later corrections do not rewrite them.\n'
    'Replay checks reproduce our pilot, not US Chess certification.\n'
    'Floats: U = higher-score opponent, D = lower-score opponent.\n\n',
  );
  String direction(int n) => n > 0
      ? 'U'
      : n < 0
      ? 'D'
      : '-';
  for (final s in event.sections.where(
    (s) => sectionId == null || s.id == sectionId,
  )) {
    out.writeln('${s.name} — ${s.tiebreakOrder.label}');
    for (final r in s.rounds) {
      out.writeln('Round ${r.number} | ${r.policy}');
      if (r.pairingInput.isEmpty) {
        out.writeln(recheckPairing(r).single);
        continue;
      }
      final input = SwissInput.decode(r.pairingInput);
      out.writeln(
        'Player\tRating\tScore\tAcceleration\tColors\tDue\tLast float\tPrevious float\tBye eligible\tAvailability\tAssignment\tScore gap\tDo-not-pair requests',
      );
      for (final p in input.players) {
        final game = r.games
            .where((g) => g.leg == 1 && (g.white == p.id || g.black == p.id))
            .firstOrNull;
        final award = r.byes.where((b) => b.player == p.id).firstOrNull;
        final opponent = game == null
            ? null
            : input.players
                  .where(
                    (x) =>
                        x.id == (game.white == p.id ? game.black : game.white),
                  )
                  .firstOrNull;
        final assignment = game == null
            ? 'Bye ${scoreText(award?.points ?? 0)}'
            : '${game.white == p.id ? 'W' : 'B'} vs ${opponent?.name ?? '?'}';
        out.writeln(
          [
            p.name.replaceAll(RegExp(r'[\t\r\n]'), ' '),
            p.rating,
            scoreText(p.score),
            scoreText(p.acceleration),
            p.colors,
            p.due,
            direction(p.lastFloat),
            direction(p.previousFloat),
            p.byeEligible ? 'Yes' : 'No',
            p.absent.isEmpty ? 'Available' : p.absent,
            assignment,
            opponent == null
                ? '-'
                : scoreText((p.pairingScore - opponent.pairingScore).abs()),
            input.players
                .where((x) => p.avoid.contains(x.id) || x.avoid.contains(p.id))
                .map((x) => x.name.replaceAll(RegExp(r'[\t\r\n]'), ' '))
                .join(', '),
          ].join('\t'),
        );
      }
      final checks = recheckPairing(r);
      out.writeln(
        checks.isEmpty ? 'Replay: matches saved proposal.' : checks.join('\n'),
      );
      out.writeln();
    }
    if (s.format == Format.swiss && !s.finished) {
      final next = swissInput(event, s);
      out.writeln('Current inputs for round ${next.round} (not posted):');
      for (final p in next.players) {
        final blocked = next.players
            .where((x) => !_compatible(p, x) && x.id != p.id)
            .map((x) => x.name)
            .join(', ');
        out.writeln(
          '${p.name}: score ${scoreText(p.score)} + acceleration ${scoreText(p.acceleration)}; '
          'colors ${p.colors}; due ${p.due}; bye ${p.byeEligible ? 'eligible' : 'ineligible'}; '
          '${p.absent.isEmpty ? 'available' : p.absent}; excluded opponents: ${blocked.isEmpty ? 'none' : blocked}.',
        );
      }
      if (s.rounds.any(
        (r) => r.games.any(
          (g) => !g.outcome.resolved && g.pairingAssumption == null,
        ),
      )) {
        out.writeln(
          'Resolve outstanding games before pairing; scores above are incomplete.',
        );
      } else {
        try {
          final preview = pairSwiss(next);
          out.writeln(
            'Next-round search: complete proposal available (${preview.nodes} search nodes).',
          );
          for (final warning in preview.warnings) {
            out.writeln(warning);
          }
        } on TournamentException catch (error) {
          out.writeln('Next-round search: ${error.message}');
        }
      }
      out.writeln();
    }
  }
  return out.toString();
}
