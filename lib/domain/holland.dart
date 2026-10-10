import 'dart:math';

import 'fixed_schedule.dart';
import 'model.dart';
import 'pairing.dart' show quadOrder;
import 'standings.dart';

/// Rule 30H / 30I: the Holland system is round-robin preliminaries that
/// qualify players for a round-robin final. It is not a pairing format of
/// its own: every stage is an ordinary round-robin section carrying
/// [Section.holland] = {group, role, qualifiers, unbalanced}. The final is
/// a fresh competition (separate entries, no carried score), as a
/// round-robin final of qualifiers is played.
const hollandPrelim = 'prelim', hollandFinal = 'final';

String hollandGroup(Section s) => (s.holland['group'] as String?) ?? '';
String hollandRole(Section s) => (s.holland['role'] as String?) ?? '';
int hollandQualifiers(Section s) => (s.holland['qualifiers'] as int?) ?? 1;
bool hollandUnbalanced(Section s) => s.holland['unbalanced'] == true;
bool isHollandPrelim(Section s) =>
    hollandGroup(s).isNotEmpty && hollandRole(s) == hollandPrelim;

/// The prelims of [group] in event order (the first is "prelim 1" for 30I).
List<Section> hollandPrelims(Event e, String group) => [
  for (final s in e.sections)
    if (isHollandPrelim(s) && hollandGroup(s) == group) s,
];

Section? hollandFinalOf(Event e, String group) => e.sections
    .where((s) => hollandGroup(s) == group && hollandRole(s) == hollandFinal)
    .firstOrNull;

/// "2 of 3 prelims finished" for the Pairings view.
({int finished, int total}) hollandProgress(Event e, String group) {
  final prelims = hollandPrelims(e, group);
  return (
    finished: prelims.where((s) => s.finished).length,
    total: prelims.length,
  );
}

/// Why the final of [group] cannot be created now, or null when it can.
String? hollandFinalProblem(Event e, String group) {
  final prelims = hollandPrelims(e, group);
  if (prelims.isEmpty) return 'This section is not a Holland preliminary.';
  if (hollandFinalOf(e, group) case final existing?) {
    return 'The final (${existing.name}) has already been created.';
  }
  final unfinished = prelims.where((s) => !s.finished).toList();
  if (unfinished.isNotEmpty) {
    final (:finished, :total) = hollandProgress(e, group);
    return '$finished of $total prelims finished. '
        '${unfinished.map((s) => s.name).join(', ')} still ${unfinished.length == 1 ? 'has' : 'have'} games to play.';
  }
  return null;
}

/// A round robin of [players] takes n−1 rounds (n for an odd field).
int _roundRobinRounds(int players) => players.isOdd ? players : players - 1;

String _freeName(Set<String> used, String Function(int n) name) {
  var n = 1;
  while (used.contains(name(n).toLowerCase())) {
    n++;
  }
  used.add(name(n).toLowerCase());
  return name(n);
}

/// Splits [players] by rating into [groups] preliminary round robins
/// ("Prelim 1", …), each sending [qualifiers] players to the final. Rule
/// 30H balances the prelims (snake seeding); rule 30I ([unbalanced]) puts
/// the top-rated in Prelim 1, the next in Prelim 2 and so on. Names skip
/// any in [taken] (by default the event's section names); boards follow the
/// event's last board.
List<Section> planHolland(
  Event event,
  Iterable<Player> players, {
  required int groups,
  required int qualifiers,
  bool unbalanced = false,
  required String Function() id,
  Iterable<String>? taken,
}) {
  final pool = players.where((p) => !p.withdrawn).toList()..sort(quadOrder);
  if (groups < 2) {
    throw const TournamentException(
      'A Holland needs at least two preliminary groups; one group is a round robin.',
    );
  }
  if (pool.length < 3 * groups) {
    throw TournamentException(
      '${pool.length} players make $groups prelims of fewer than three; use fewer groups.',
    );
  }
  final smallest = pool.length ~/ groups;
  if (qualifiers < 1 || qualifiers >= smallest) {
    throw TournamentException(
      'Each prelim of $smallest players can send 1 to ${smallest - 1} to the final.',
    );
  }
  final rosters = List.generate(groups, (_) => <String>[]);
  if (unbalanced) {
    // 30I: consecutive slices by rating, the extra players in the top groups.
    var offset = 0;
    for (var g = 0; g < groups; g++) {
      final size = pool.length ~/ groups + (g < pool.length % groups ? 1 : 0);
      rosters[g].addAll(pool.sublist(offset, offset + size).map((p) => p.id));
      offset += size;
    }
  } else {
    // 30H: snake seeding so every prelim has similar strength.
    for (final (index, p) in pool.indexed) {
      final row = index ~/ groups, slot = index % groups;
      rosters[row.isEven ? slot : groups - 1 - slot].add(p.id);
    }
  }
  final used = {
    for (final name in taken ?? event.sections.map((s) => s.name))
      name.toLowerCase(),
  };
  final group = id();
  var board = nextBoard(event.sections);
  return [
    for (final roster in rosters)
      () {
        final section = Section(
          id: id(),
          name: _freeName(used, (n) => 'Prelim $n'),
          players: roster,
          format: Format.roundRobin,
          plannedRounds: _roundRobinRounds(roster.length),
          boardStart: board,
          holland: {
            'group': group,
            'role': hollandPrelim,
            'qualifiers': qualifiers,
            'unbalanced': unbalanced,
          },
        );
        board += (roster.length + 1) ~/ 2;
        return section;
      }(),
  ];
}

/// The final of a Holland [group]: a round robin of the qualifiers with
/// separate entries (the same people, a fresh score), ready to add to the
/// event as `players: [...event.players, ...entries]`.
typedef HollandFinal = ({Section section, List<Player> entries});

/// Who advances from [prelim] (its index in the group is [index]): the top
/// [hollandQualifiers] by standings, ties broken by the event's tie-breaks
/// (rule 34F order unless the event posts its own). Under rule 30I every
/// plus score in Prelim 1 qualifies, the top two from Prelim 2 and the
/// winner of each other prelim. A tie on every tie-break at the cut is
/// broken by lot (34E13) with [seed], or refused when no seed is given.
List<Player> hollandQualifiersOf(
  Event event,
  Section prelim,
  int index, {
  int? seed,
}) {
  final rows = standings(
    event,
    prelim,
    forPairing: true,
  ).where((row) => !row.player.withdrawn).toList();
  int count;
  if (hollandUnbalanced(prelim)) {
    if (index == 0) {
      final plus = rows.where((row) => row.points > row.played).length;
      count = plus == 0 ? 1 : plus;
    } else {
      count = index == 1 ? 2 : 1;
    }
  } else {
    count = hollandQualifiers(prelim);
  }
  count = min(count, rows.length);
  if (count <= 0 || count >= rows.length) {
    return rows.take(count).map((row) => row.player).toList();
  }
  final cut = rows[count - 1];
  if (!sharePlace(cut, rows[count], tiebreaks: true)) {
    return rows.take(count).map((row) => row.player).toList();
  }
  final tied = rows
      .where((row) => sharePlace(row, cut, tiebreaks: true))
      .toList();
  final sure = rows.where((row) => row.rank < cut.rank).length;
  final places = count - sure;
  if (seed == null) {
    throw TournamentException(
      '${tied.map((row) => row.player.name).join(', ')} are tied on every tie-break for the last ${places == 1 ? 'place' : '$places places'} in the final from ${prelim.name}. Rule 34E13 breaks it by lot.',
    );
  }
  final drawn = [...tied]..shuffle(Random(seed));
  return [
    for (final row in rows.take(sure)) row.player,
    for (final row in drawn.take(places)) row.player,
  ];
}

/// Builds the final of [group] once every prelim has finished. Each
/// qualifier gets a separate entry in the final, so the final's standings
/// start from zero while the prelim games stay in their sections for the
/// rating report.
HollandFinal finalsFor(
  Event event,
  String group,
  String Function() id, {
  int? seed,
}) {
  if (hollandFinalProblem(event, group) case final problem?) {
    throw TournamentException(problem);
  }
  final prelims = hollandPrelims(event, group);
  final entries = <Player>[];
  final seen = <String>{};
  for (final (index, prelim) in prelims.indexed) {
    for (final p in hollandQualifiersOf(event, prelim, index, seed: seed)) {
      final person = p.personId ?? p.id;
      if (!seen.add(person)) continue;
      entries.add(
        Player.fromJson({
          ...p.toJson(),
          'id': id(),
          'personId': person,
          'byes': <String, int>{},
          'withdrawn': false,
        }),
      );
    }
  }
  if (entries.length < 2) {
    throw const TournamentException(
      'Fewer than two players qualified for the final.',
    );
  }
  final model = prelims.first;
  final used = {for (final s in event.sections) s.name.toLowerCase()};
  final section = Section(
    id: id(),
    name: _freeName(used, (n) => n == 1 ? 'Final' : 'Final $n'),
    players: [for (final p in entries) p.id],
    format: Format.roundRobin,
    plannedRounds: _roundRobinRounds(entries.length),
    boardStart: nextBoard(event.sections),
    timeControl: model.timeControl,
    rrTable: model.rrTable,
    unrated: model.unrated,
    holland: {
      'group': group,
      'role': hollandFinal,
      'qualifiers': hollandQualifiers(model),
      'unbalanced': hollandUnbalanced(model),
    },
  );
  // A field the Crenshaw tables do not cover falls back to the circle method.
  if (section.rrTable == crenshawTable && entries.length > crenshawMaxPlayers) {
    return (section: section.copy(rrTable: ''), entries: entries);
  }
  return (section: section, entries: entries);
}
