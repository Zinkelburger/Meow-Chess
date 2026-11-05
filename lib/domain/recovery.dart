import 'model.dart';

/// What kind of landmark a [RecoveryMark] is.
enum RecoveryKind { pairing, unpairing, import, transfer }

/// A state worth going back to by name, such as "Before round 3 pairings".
/// It describes the state *before* a history step: the step's parent.
class RecoveryMark {
  const RecoveryMark(
    this.kind,
    this.title,
    this.detail, {
    this.sectionIds = const [],
    this.round = 0,
    this.players = 0,
  });
  final RecoveryKind kind;
  final String title, detail;

  /// Sections the step paired, unpaired or moved players into.
  final List<String> sectionIds;

  /// For pairing, the first round the step posted; for unpairing, the first
  /// round it removed.
  final int round;

  /// For an import, how many entries it added.
  final int players;

  @override
  String toString() => '$title · $detail';
}

/// A [RecoveryMark] placed in the event's history: [node] is the saved state
/// to go back to, [step] the change that followed it, at [timestamp].
class RecoveryPoint {
  const RecoveryPoint(this.node, this.step, this.mark, this.timestamp);
  final int node, step;
  final RecoveryMark mark;
  final String timestamp;
}

/// The landmarks a history step from [before] to [after] creates: each
/// names [before] as a state a director may want back. Side-game sections
/// are left out; they are not part of the tournament's schedule.
List<RecoveryMark> recoveryMarks(Event before, Event after) {
  final marks = <RecoveryMark>[];
  final paired = <int, List<Section>>{}, unpaired = <int, List<Section>>{};
  for (final s in after.sections.where((s) => !s.sideGames)) {
    final old = before.sections.where((x) => x.id == s.id).firstOrNull;
    final was = old?.rounds.length ?? 0;
    if (s.rounds.length > was) (paired[was + 1] ??= []).add(s);
    if (s.rounds.length < was) {
      (unpaired[s.rounds.length + 1] ??= []).add(s);
    }
  }
  // Past three names a list stops reading at a glance.
  String names(List<Section> sections) => sections.length > 3
      ? '${sections.length} sections'
      : sections.map((s) => s.name).join(', ');
  for (final MapEntry(key: n, value: sections) in paired.entries) {
    marks.add(
      RecoveryMark(
        RecoveryKind.pairing,
        'Before round $n pairings',
        names(sections),
        sectionIds: [for (final s in sections) s.id],
        round: n,
      ),
    );
  }
  for (final MapEntry(key: n, value: sections) in unpaired.entries) {
    marks.add(
      RecoveryMark(
        RecoveryKind.unpairing,
        'Before unpairing round $n',
        names(sections),
        sectionIds: [for (final s in sections) s.id],
        round: n,
      ),
    );
  }
  final known = {for (final p in before.players) p.id};
  final added = after.players.where((p) => !known.contains(p.id)).length;
  // One registration is routine; an import changes the roster wholesale.
  if (added > 1) {
    marks.add(
      RecoveryMark(
        RecoveryKind.import,
        'Before importing $added players',
        switch (before.players.length) {
          0 => 'the roster was empty',
          1 => '1 already registered',
          final n => '$n already registered',
        },
        players: added,
      ),
    );
  }
  if (after.transitions.length > before.transitions.length) {
    final targets = {
      for (final t in after.transitions.skip(before.transitions.length))
        t['target'] as String,
    };
    final sections = [
      for (final s in after.sections)
        if (targets.contains(s.id)) s,
    ];
    marks.add(
      RecoveryMark(
        RecoveryKind.transfer,
        'Before moving players',
        sections.isEmpty ? '' : 'to ${names(sections)}',
        sectionIds: [for (final s in sections) s.id],
      ),
    );
  }
  return marks;
}

/// The event at a glance, a line per section: how far it has got. Shown
/// beside a point in history so the director can tell what going there
/// means before going.
List<String> stateSummary(Event e) {
  final lines = <String>[];
  for (final s in e.sections.where((s) => !s.sideGames)) {
    final posted = s.rounds.length;
    final last = s.rounds.lastOrNull;
    final games = last?.games.length ?? 0;
    final done = last?.games.where((g) => g.outcome.resolved).length ?? 0;
    // A knockout runs to its bracket and a ladder to its batches, so only
    // the scheduled formats say "of N".
    final of = s.format == Format.knockout || s.format == Format.ladder
        ? ''
        : ' of ${s.plannedRounds}';
    final where = posted == 0
        ? 'not paired yet'
        : last!.complete
        ? 'round $posted$of complete'
        : 'round $posted$of paired, '
              '$done of $games ${games == 1 ? 'result' : 'results'} in';
    lines.add('${s.name}: $where');
  }
  final players = e.players.length;
  lines.add('$players ${players == 1 ? 'player' : 'players'} registered');
  return lines;
}
