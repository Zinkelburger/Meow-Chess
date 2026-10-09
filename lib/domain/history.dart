import 'dart:convert';

import 'bye_policy.dart';
import 'model.dart';
import 'tiebreaks.dart';

/// One saved state of the event. Every command creates a node whose parent is
/// the node the event was at, so going back and changing something starts a
/// branch instead of discarding the later states.
class HistoryNode {
  const HistoryNode({
    required this.id,
    required this.parent,
    required this.action,
    required this.timestamp,
    required this.lastVisit,
  });
  final int id;
  final int? parent;
  final String action, timestamp;

  /// Audit id of the last time the event was at this node; forward follows
  /// the most recently visited child, like a chess GUI returning to the line
  /// it came from.
  final int lastVisit;
}

/// Where one history row sits in the drawn graph. Lanes are columns; [top]
/// and [bottom] hold, per lane, the child whose line enters from above or
/// continues below (null when the lane is empty there).
class GraphRow {
  const GraphRow(this.node, this.lane, this.top, this.bottom, this.merges);
  final HistoryNode node;
  final int lane;
  final List<int?> top, bottom;

  /// Lanes whose branch forks from this node.
  final List<int> merges;
}

enum NodeStyle { past, future, branch }

class HistoryGraph {
  HistoryGraph(Iterable<HistoryNode> nodes, this.head)
    : nodes = {for (final n in nodes) n.id: n} {
    for (final n in this.nodes.values) {
      if (n.parent != null) (children[n.parent!] ??= []).add(n.id);
    }
    for (int? id = head; id != null; id = this.nodes[id]?.parent) {
      past.add(id);
    }
    for (var id = forwardOf(head); id != null; id = forwardOf(id)) {
      future.add(id);
    }
  }
  final Map<int, HistoryNode> nodes;
  final int? head;
  final Map<int, List<int>> children = {};

  /// The current node and everything before it.
  final Set<int> past = {};

  /// The line Forward walks, from the current node to its tip.
  final List<int> future = [];

  int? get back => nodes[head]?.parent;
  int? get forward => future.firstOrNull;

  int? forwardOf(int? id) {
    final next = children[id];
    if (next == null || next.isEmpty) return null;
    return next.reduce(
      (a, b) => nodes[a]!.lastVisit >= nodes[b]!.lastVisit ? a : b,
    );
  }

  NodeStyle style(int id) => past.contains(id)
      ? NodeStyle.past
      : future.contains(id)
      ? NodeStyle.future
      : NodeStyle.branch;

  /// Each saved side branch stays addressable by its first operation, including
  /// any further forks below it. Collapsing only changes the presentation.
  late final Map<int, List<int>> branches = () {
    final result = <int, List<int>>{};
    final roots = <int, int>{};
    final ids = nodes.keys.toList()..sort();
    for (final id in ids) {
      if (style(id) != NodeStyle.branch) continue;
      final root = roots[nodes[id]!.parent] ?? id;
      roots[id] = root;
      (result[root] ??= []).add(id);
    }
    return result;
  }();

  HistoryGraph folded(Set<int> expanded) {
    final hidden = <int>{
      for (final entry in branches.entries)
        if (!expanded.contains(entry.key)) ...entry.value.skip(1),
    };
    return HistoryGraph(
      nodes.values.where((n) => !hidden.contains(n.id)),
      head,
    );
  }

  /// Operations to undo (newest first) and apply (oldest first), through the
  /// common ancestor. This also describes restores across saved branches.
  ({List<int> undo, List<int> apply}) pathTo(int target) {
    if (!nodes.containsKey(target)) throw ArgumentError.value(target);
    final apply = <int>[];
    int? common = target;
    while (common != null && !past.contains(common)) {
      apply.add(common);
      common = nodes[common]!.parent;
    }
    final undo = <int>[];
    for (var id = head; id != common && id != null; id = nodes[id]!.parent) {
      undo.add(id);
    }
    return (undo: undo, apply: apply.reversed.toList());
  }

  /// Rows newest first. The current line (past and future) always keeps lane
  /// 0 so side branches hang off a straight spine.
  late final List<GraphRow> rows = () {
    final rows = <GraphRow>[];
    // Each lane waits for the parent of the child drawn last in it; lane 0
    // starts reserved for the tip of the current line, with no line above it.
    final waiting = <int?>[future.lastOrNull ?? head];
    final from = <int?>[null];
    final ids = nodes.keys.toList()..sort((a, b) => b - a);
    for (final id in ids) {
      final node = nodes[id]!;
      final top = [...from];
      final joining = [
        for (var i = 0; i < waiting.length; i++)
          if (waiting[i] == id) i,
      ];
      int lane;
      if (joining.isEmpty) {
        lane = waiting.indexOf(null, 1);
        if (lane < 0) {
          lane = waiting.length;
          waiting.add(null);
          from.add(null);
          top.add(null);
        }
      } else {
        lane = joining.first;
      }
      for (final m in joining.skip(1)) {
        waiting[m] = null;
        from[m] = null;
      }
      waiting[lane] = node.parent;
      from[lane] = node.parent == null ? null : id;
      while (waiting.length > 1 && waiting.last == null) {
        waiting.removeLast();
        from.removeLast();
      }
      rows.add(GraphRow(node, lane, top, [...from], joining.skip(1).toList()));
    }
    return rows;
  }();
}

String _name(Event before, Event after, String id) =>
    (after.players.where((p) => p.id == id).firstOrNull ??
            before.players.where((p) => p.id == id).firstOrNull)
        ?.name ??
    'Unknown player';

String _list(Iterable<String> names) {
  final all = names.toList();
  return all.length <= 4
      ? all.join(', ')
      : '${all.take(3).join(', ')} and ${all.length - 3} more';
}

String _format(Format f) => switch (f) {
  Format.swiss => 'Swiss',
  Format.quad => 'Quad',
  Format.roundRobin => 'Round robin',
};

String _short(String text) {
  final line = text.replaceAll('\n', ' ').trim();
  if (line.isEmpty) return '(empty)';
  // Count code points, so an emoji is never cut in half.
  final runes = line.runes;
  return runes.length > 40
      ? '“${String.fromCharCodes(runes.take(39))}…”'
      : '“$line”';
}

/// Plain-language list of what differs from [before] to [after], for
/// reviewing a history step or what a restore would change.
List<String> describeChanges(
  Event before,
  Event after, {
  bool includePrevious = true,
}) {
  final out = <String>[];
  String value(Object before, Object after) =>
      includePrevious ? '$before → $after' : '$after';
  String name(String id) => _name(before, after, id);
  final a = before.toJson(), b = after.toJson();
  for (final (key, label) in [
    ('name', 'Event name'),
    ('date', 'Date'),
    ('endDate', 'End date'),
    ('city', 'City'),
    ('state', 'State'),
    ('zip', 'ZIP code'),
    ('level', 'Rating report section type'),
    ('timeControl', 'Time control'),
    ('venue', 'Venue'),
    ('tdId', 'TD ID'),
    ('assistantTdId', 'Assistant chief TD ID'),
    ('otherTdIds', 'Other TD IDs'),
    ('affiliateId', 'Affiliate ID'),
    ('notes', 'Event notes'),
    ('submission', 'Submission notes'),
    ('policy', 'Event policy'),
    ('backupFolder', 'Backup folder'),
  ]) {
    if (a[key] != b[key]) {
      out.add('$label: ${value(_short('${a[key]}'), _short('${b[key]}'))}');
    }
  }
  if (before.practice != after.practice) {
    out.add(
      after.practice ? 'Marked as a practice copy' : 'Practice mark removed',
    );
  }

  if (before.useTiebreaks != after.useTiebreaks) {
    out.add(
      after.useTiebreaks
          ? 'Tie-break rankings enabled'
          : 'Tie-break rankings disabled',
    );
  }
  if (before.tiebreaks.join('|') != after.tiebreaks.join('|')) {
    out.add(
      after.tiebreaks.isEmpty
          ? 'Tie-break order: US Chess default'
          : 'Tie-break order: ${after.tiebreaks.map(tiebreakLabel).join(', ')}',
    );
  }
  if (jsonEncode(before.rosterSource) != jsonEncode(after.rosterSource)) {
    out.add('Roster source changed');
  }
  if (before.online != after.online) {
    out.add(after.online ? 'Marked as an online event' : 'Online mark removed');
  }
  if (before.rulings.length != after.rulings.length) {
    final added = after.rulings.length - before.rulings.length;
    out.add(
      added > 0
          ? 'Logged ${added == 1 ? 'a' : '$added'} ${after.rulings.last['kind'] ?? 'ruling'}${added == 1 ? '' : 's'}: ${_short('${after.rulings.last['text'] ?? ''}')}'
          : 'Removed ${-added == 1 ? 'a log entry' : '${-added} log entries'}',
    );
  }

  final oldPlayers = {for (final p in before.players) p.id: p};
  final newPlayers = {for (final p in after.players) p.id: p};
  final added = after.players.where((p) => !oldPlayers.containsKey(p.id));
  final removed = before.players.where((p) => !newPlayers.containsKey(p.id));
  if (added.isNotEmpty) {
    out.add(
      'Added ${added.length == 1 ? '' : '${added.length} players: '}${_list(added.map((p) => p.name))}',
    );
  }
  if (removed.isNotEmpty) {
    out.add(
      'Removed ${removed.length == 1 ? '' : '${removed.length} players: '}${_list(removed.map((p) => p.name))}',
    );
  }
  for (final p in after.players) {
    final o = oldPlayers[p.id];
    if (o == null) continue;
    final edits = [
      if (o.name != p.name) 'renamed from ${o.name}',
      if (o.rating != p.rating) 'rating ${value(o.rating, p.rating)}',
      if (o.pairingRating != p.pairingRating)
        'pairing rating ${value(o.pairingRating == 0 ? 'published' : o.pairingRating, p.pairingRating == 0 ? 'published' : p.pairingRating)}',
      if (o.prizeRating != p.prizeRating)
        'prize rating ${value(o.prizeRating == 0 ? 'published' : o.prizeRating, p.prizeRating == 0 ? 'published' : p.prizeRating)}',
      if (o.ratingNote != p.ratingNote)
        'rating cause ${_short(p.ratingNote.isEmpty ? '(none)' : p.ratingNote)}',
      if (o.foreignRating != p.foreignRating ||
          o.foreignFederation != p.foreignFederation)
        'foreign rating ${p.foreignRating == 0 ? '(none)' : '${p.foreignFederation} ${p.foreignRating}'}',
      if (o.computer != p.computer)
        p.computer ? 'marked computer entrant' : 'no longer a computer entrant',
      for (final r in p.irrevocableByes.difference(o.irrevocableByes))
        'round $r bye declared irrevocable',
      for (final r in o.irrevocableByes.difference(p.irrevocableByes))
        'round $r irrevocable declaration withdrawn',
      if (o.state != p.state)
        'state ${value(_short(o.state), _short(p.state))}',
      if (o.reportName != p.reportName)
        'rating report name ${value(_short(o.reportName), _short(p.reportName))}',
      if (o.personId != p.personId) 'linked person identity changed',
      if (o.source != p.source) 'registration source changed',
      if (jsonEncode(o.ratingEvidence) != jsonEncode(p.ratingEvidence))
        'rating evidence changed',
      if (o.membershipEvidence.toString() != p.membershipEvidence.toString())
        'US Chess membership: ${p.membershipEvidence['expiration'] ?? 'date unavailable'} (${p.membershipEvidence['status'] ?? 'unknown'})',
      if (o.memberId != p.memberId)
        'US Chess ID ${value(o.memberId.isEmpty ? '(none)' : o.memberId, p.memberId.isEmpty ? '(none)' : p.memberId)}',
      if (o.checkedIn != p.checkedIn)
        p.checkedIn ? 'checked in' : 'check-in cleared',
      if (o.withdrawn != p.withdrawn) p.withdrawn ? 'withdrawn' : 'reinstated',
      if (o.club != p.club) 'club ${value(_short(o.club), _short(p.club))}',
      if (o.team != p.team) 'team ${value(_short(o.team), _short(p.team))}',
      for (final id in p.avoid.difference(o.avoid))
        'do not pair with ${_name(before, after, id)}',
      for (final id in o.avoid.difference(p.avoid))
        'may pair with ${_name(before, after, id)} again',
      if (o.notes != p.notes) 'notes ${_short(p.notes)}',
      if (o.registrationNote != p.registrationNote)
        'registration note ${_short(p.registrationNote)}',
      if (o.house != p.house)
        p.house ? 'marked house player' : 'no longer house player',
      for (final r in {...o.byes.keys, ...p.byes.keys}.toList()..sort())
        if (o.byes[r] != p.byes[r])
          p.byes[r] == null
              ? 'round $r bye cancelled'
              : 'round $r bye (${scoreText(p.byes[r]!)} pt)',
    ];
    if (edits.isNotEmpty) out.add('${p.name}: ${edits.join(', ')}');
  }

  final oldSections = {for (final s in before.sections) s.id: s};
  final newIds = after.sections.map((s) => s.id).toSet();
  for (final s in before.sections.where((s) => !newIds.contains(s.id))) {
    out.add('Removed section ${s.name}');
  }
  for (final s in after.sections) {
    final o = oldSections[s.id];
    if (o == null) {
      out.add('Created section ${s.name} (${s.players.length} players)');
      continue;
    }
    final label = s.name;
    final settings = [
      if (o.name != s.name) 'renamed from ${o.name}',
      if (o.format != s.format)
        'format ${value(_format(o.format), _format(s.format))}',
      if (o.plannedRounds != s.plannedRounds)
        'rounds ${value(o.plannedRounds, s.plannedRounds)}',
      if (o.boardStart != s.boardStart)
        'first board ${value(o.boardStart, s.boardStart)}',
      if (o.ratingCeiling != s.ratingCeiling)
        'rating ceiling ${value(o.ratingCeiling, s.ratingCeiling)}',
      if (o.timeControl != s.timeControl)
        'time control ${value(_short(o.timeControl), _short(s.timeControl))}',
      if (o.sideGames != s.sideGames)
        s.sideGames ? 'side games enabled' : 'side games disabled',
      if (jsonEncode(o.quadPairings) != jsonEncode(s.quadPairings))
        'quad pairing schedule changed',
      if (o.doubleGames != s.doubleGames)
        s.doubleGames ? 'double games' : 'single games',
      if (jsonEncode(o.byeRules) != jsonEncode(s.byeRules))
        'bye policy: ${ByePolicy.fromJson(s.byeRules).describe()}',
      if (jsonEncode(o.prizes) != jsonEncode(s.prizes)) 'prize table changed',
    ];
    if (settings.isNotEmpty) out.add('$label: ${settings.join(', ')}');
    final joined = s.players.where((id) => !o.players.contains(id));
    final left = o.players.where((id) => !s.players.contains(id));
    if (joined.isNotEmpty) out.add('$label: added ${_list(joined.map(name))}');
    if (left.isNotEmpty) out.add('$label: removed ${_list(left.map(name))}');
    if (joined.isEmpty &&
        left.isEmpty &&
        jsonEncode(o.players) != jsonEncode(s.players)) {
      out.add('$label: player order changed');
    }

    for (final r in o.rounds.skip(s.rounds.length)) {
      out.add('$label round ${r.number} removed');
    }
    for (final r in s.rounds) {
      final prefix = '$label round ${r.number}';
      final old = o.rounds.where((x) => x.number == r.number).firstOrNull;
      if (old == null) {
        out.add(
          '$label round ${r.number} paired (${r.games.length} boards${r.byes.isEmpty ? '' : ', ${r.byes.length} byes'})',
        );
        continue;
      }
      if (old.startedAt == null && r.startedAt != null) {
        out.add('$label round ${r.number} started');
      } else if (old.startedAt != null && r.startedAt == null) {
        out.add('$label round ${r.number} start cleared');
      }
      if (old.startedAt != null &&
          r.startedAt != null &&
          old.startedAt != r.startedAt) {
        out.add('$prefix start time ${value(old.startedAt!, r.startedAt!)}');
      }
      if (old.postedAt != r.postedAt) out.add('$prefix posting time changed');
      if (old.policy != r.policy) out.add('$prefix pairing policy changed');
      if (old.note != r.note) out.add('$prefix note ${_short(r.note)}');
      final oldGames = {for (final g in old.games) g.id: g};
      final gameIds = r.games.map((g) => g.id).toSet();
      var repaired = 0;
      for (final g in r.games) {
        final x = oldGames[g.id];
        final pairing = '${name(g.white)} – ${name(g.black)}';
        if (x == null) {
          repaired++;
          continue;
        }
        if (x.white != g.white || x.black != g.black) {
          out.add(
            x.white == g.black && x.black == g.white
                ? '$prefix board ${g.board}: colors swapped ($pairing)'
                : '$prefix board ${g.board}: now $pairing',
          );
        } else if (x.board != g.board) {
          out.add('$prefix $pairing: board ${value(x.board, g.board)}');
        }
        if (x.outcome != g.outcome) {
          out.add(
            '$prefix board ${g.board} $pairing: ${value(x.outcome.label, g.outcome.label)}',
          );
        }
        if (x.leg != g.leg) {
          out.add('$prefix board ${g.board}: game leg ${value(x.leg, g.leg)}');
        }
        if (x.pairingAssumption != g.pairingAssumption) {
          out.add(
            '$prefix board ${g.board}: pairing assumption '
            '${value(x.pairingAssumption?.label ?? '(none)', g.pairingAssumption?.label ?? '(none)')}',
          );
        }
        if (x.pairingReason != g.pairingReason) {
          out.add(
            '$prefix board ${g.board}: pairing reason ${_short(g.pairingReason)}',
          );
        }
        if (x.note != g.note) {
          out.add('$prefix board ${g.board} note ${_short(g.note)}');
        }
      }
      repaired += old.games.where((g) => !gameIds.contains(g.id)).length;
      if (repaired > 0) out.add('$prefix pairings edited');
      final oldByes = {for (final x in old.byes) x.player: x.points};
      final newByes = {for (final x in r.byes) x.player: x.points};
      for (final id in {...oldByes.keys, ...newByes.keys}) {
        if (oldByes[id] == newByes[id]) {
          final previous = old.byes.firstWhere((b) => b.player == id);
          final current = r.byes.firstWhere((b) => b.player == id);
          if (previous.reason != current.reason ||
              previous.allocated != current.allocated) {
            out.add('$prefix: ${name(id)} bye details changed');
          }
          continue;
        }
        out.add(
          newByes[id] == null
              ? '$prefix: ${name(id)} bye removed'
              : '$prefix: ${name(id)} bye (${scoreText(newByes[id]!)} pt)',
        );
      }
    }
  }
  if (after.transitions.length > before.transitions.length) {
    out.add('Recorded a section transfer');
  } else if (after.transitions.length < before.transitions.length) {
    out.add('Section transfer record removed');
  } else if (jsonEncode(before.transitions) != jsonEncode(after.transitions)) {
    out.add('Section transfer record changed');
  }
  if (before.sections.length == after.sections.length &&
      before.sections
          .map((s) => s.id)
          .toSet()
          .containsAll(after.sections.map((s) => s.id)) &&
      before.sections.map((s) => s.id).join('|') !=
          after.sections.map((s) => s.id).join('|')) {
    out.add('Section order changed');
  }
  // A future persisted field must never make a restore look unchanged merely
  // because it has not yet acquired a specialized description above.
  if (out.isEmpty &&
      before.copy(revision: 0).encode() != after.copy(revision: 0).encode()) {
    out.add('Other event details changed');
  }
  return out;
}

/// A history row: what happened, in the TD's words, and where.
typedef HistoryStep = ({String title, String context});

/// Headline for one history step. A result entry or correction reads as the
/// game itself (players and score) with its section, round and board beneath,
/// instead of as a list of field changes.
HistoryStep summarizeStep(Event before, Event after) {
  final items = describeChanges(before, after, includePrevious: false);
  final results = <(Section, Round, Game, Game)>[];
  var reopenedFrom = 0;
  for (final s in after.sections) {
    final o = before.sections.where((x) => x.id == s.id).firstOrNull;
    if (o == null) continue;
    if (o.rounds.length > s.rounds.length) reopenedFrom = s.rounds.length + 1;
    for (final r in s.rounds) {
      final old = o.rounds.where((x) => x.number == r.number).firstOrNull;
      final games = {for (final g in old?.games ?? <Game>[]) g.id: g};
      for (final g in r.games) {
        final x = games[g.id];
        if (x != null && x.outcome != g.outcome) results.add((s, r, x, g));
      }
    }
  }
  if (results.length == 1) {
    final (s, r, x, g) = results.single;
    final pairing =
        '${_name(before, after, g.white)} – ${_name(before, after, g.black)}';
    return (
      title: g.outcome == Outcome.unreported
          ? '$pairing: result cleared'
          : '$pairing  ${g.outcome.label}',
      context: [
        '${s.name} · Round ${r.number} · Board ${g.board}',
        if (x.outcome != Outcome.unreported && g.outcome != Outcome.unreported)
          'was ${x.outcome.label}',
        if (reopenedFrom > 0) 'round $reopenedFrom onward unpaired',
      ].join(' · '),
    );
  }
  if (items.isEmpty) return (title: 'No visible change', context: '');
  final first = items.first;
  final colon = first.indexOf(': ');
  return (
    title: colon < 0 || colon + 2 >= first.length
        ? first
        : first.substring(0, colon + 2) +
              first[colon + 2].toUpperCase() +
              first.substring(colon + 3),
    context: items.length == 1
        ? ''
        : 'and ${items.length - 1} more ${items.length == 2 ? 'change' : 'changes'}',
  );
}

/// Play recorded in [from] that moving to [to] would take away, when that is
/// more than an ordinary undo: a round with play removed, a round start
/// cleared, or more than one result reverted. Undoing a single result entry
/// is routine and needs no warning.
List<String> playLost(Event from, Event to) {
  final out = <String>[];
  var results = 0, structural = false;
  for (final s in from.sections) {
    final target = to.sections.where((x) => x.id == s.id).firstOrNull;
    for (final r in s.rounds.where((r) => r.hasPlay)) {
      final other = target?.rounds
          .where((x) => x.number == r.number)
          .firstOrNull;
      final games = {for (final g in other?.games ?? <Game>[]) g.id: g};
      final lost = r.games
          .where(
            (g) =>
                g.outcome != Outcome.unreported &&
                games[g.id]?.outcome != g.outcome,
          )
          .length;
      final removed = other == null;
      final start = !removed && r.startedAt != null && other.startedAt == null;
      results += lost;
      structural |= removed || start;
      if (lost == 0 && !removed && !start) continue;
      out.add(
        '${s.name} round ${r.number}: ${[if (removed) 'the round is removed', if (lost > 0) '$lost ${lost == 1 ? 'result' : 'results'}', if (start) 'the round start'].join(', ')}',
      );
    }
  }
  return structural || results > 1 ? out : const [];
}

/// A selective reversal is offered only for a transaction that changed one
/// game's result. Pairing edits, imports, and reopen operations stay atomic.
({String gameId, Outcome outcome})? reversibleResult(
  Event before,
  Event after,
  Event current,
) {
  final oldGames = {for (final g in before.games) g.id: g};
  final changed = after.games
      .where((g) => oldGames[g.id]?.outcome != g.outcome)
      .toList();
  if (changed.length != 1) return null;
  final g = changed.single, old = oldGames[changed.single.id];
  if (old == null) return null;
  final normalized = before.copy(
    revision: after.revision,
    sections: [
      for (final s in before.sections)
        s.copy(
          rounds: [
            for (final r in s.rounds)
              r.copy(games: [for (final x in r.games) x.id == g.id ? g : x]),
          ],
        ),
    ],
  );
  if (normalized.encode() != after.encode()) return null;
  final live = current.games.where((x) => x.id == g.id).firstOrNull;
  if (live == null ||
      live.white != g.white ||
      live.black != g.black ||
      live.outcome != g.outcome ||
      live.leg != g.leg) {
    return null;
  }
  return (gameId: g.id, outcome: old.outcome);
}
