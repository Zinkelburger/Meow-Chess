// Writes synthetic sample events for manual testing:
//   dart run tools/make_sample_events.dart [output-dir]   (default samples/events)
// Each step is its own committed revision, so history and Undo have content.
// Results are seeded, so every run produces the same games.
import 'dart:io';
import 'dart:math';

import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

final _random = Random(2026);
var _ids = 0;
String _id() => 'sample-${_ids++}';

void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'samples/events' : args.single)
    ..createSync(recursive: true);
  _swissInProgress('${out.path}/fall_open_round3.meow');
  _quadsFinished('${out.path}/saturday_quads_finished.meow');
}

class _Writer {
  _Writer(String path) : _repo = _fresh(path);
  final SqliteEventRepository _repo;
  late Event event;

  static SqliteEventRepository _fresh(String path) {
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    stdout.writeln('Writing $path');
    return SqliteEventRepository(path);
  }

  void commit(String action, Event next) => event = _repo.commit(
    next,
    expectedRevision: event.revision,
    action: action,
  );

  void start(Event first) =>
      event = _repo.commit(first, expectedRevision: 0, action: 'Create event');

  void close() => _repo.close();

  Section section(String id) => event.sections.firstWhere((s) => s.id == id);

  void replaceSection(String action, Section next) => commit(
    action,
    event.copy(
      sections: [for (final s in event.sections) s.id == next.id ? next : s],
    ),
  );

  void post(String sectionId) {
    final s = section(sectionId);
    final round = proposeRound(event, s, _id).copy(
      postedAt: DateTime.now().toUtc().toIso8601String(),
    );
    replaceSection(
      'Post ${s.name} round ${round.number}',
      s.copy(format: pairingFormat(s), rounds: [...s.rounds, round]),
    );
  }

  void begin(String sectionId) {
    final s = section(sectionId);
    replaceSection(
      'Start round',
      s.copy(
        rounds: [
          ...s.rounds.take(s.rounds.length - 1),
          s.rounds.last.copy(
            startedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ],
      ),
    );
  }

  /// Records results for the current round; [leaveOpen] boards stay unreported.
  void play(String sectionId, {Set<int> leaveOpen = const {}}) {
    for (final g in section(sectionId).rounds.last.games) {
      if (leaveOpen.contains(g.board)) continue;
      final s = section(sectionId);
      final outcome = _outcome(
        event.player(g.white).rating,
        event.player(g.black).rating,
      );
      replaceSection(
        'Result, board ${g.board}',
        s.copy(
          rounds: [
            ...s.rounds.take(s.rounds.length - 1),
            s.rounds.last.copy(
              games: [
                for (final x in s.rounds.last.games)
                  x.id == g.id ? x.copy(outcome: outcome) : x,
              ],
            ),
          ],
        ),
      );
    }
  }
}

/// Rating-weighted result with a fixed draw band and the odd forfeit.
Outcome _outcome(int white, int black) {
  final roll = _random.nextDouble();
  if (roll < 0.03) return Outcome.blackForfeit;
  final rw = white == 0 ? 1200 : white, rb = black == 0 ? 1200 : black;
  final expected = 1 / (1 + pow(10, (rb - rw) / 400));
  final r = _random.nextDouble();
  const draw = 0.18;
  if (r < expected - draw / 2) return Outcome.whiteWin;
  if (r < expected + draw / 2) return Outcome.draw;
  return Outcome.blackWin;
}

List<Player> _roster(String csv) => [
  for (final row in parseRoster(File(csv).readAsStringSync()))
    if (row.player case final p?)
      Player(
        id: _id(),
        name: p.name,
        memberId: p.memberId,
        rating: p.rating,
        club: p.club,
        state: p.state,
        checkedIn: true,
        source: p.source,
      ),
];

/// Two-section Swiss: rounds 1–2 complete, round 3 started with boards open,
/// one withdrawal and one requested round-4 bye.
void _swissInProgress(String path) {
  final w = _Writer(path);
  w.start(
    Event(
      id: _id(),
      name: 'Fall Open (sample)',
      date: '2026-10-17',
      endDate: '2026-10-18',
      timeControl: 'G/90 d5',
      venue: 'Meow Chess Club, Main Hall',
      city: 'Boston',
      state: 'MA',
      zip: '02116',
      practice: true,
    ),
  );
  w.commit(
    'Import players',
    w.event.copy(players: _roster('samples/swiss_open_36.csv')),
  );
  final players = [...w.event.players]
    ..sort((a, b) => b.rating.compareTo(a.rating));
  // A late withdrawal and a half-point bye request, as on a real Sunday.
  final withdrawn = players[30].id, bye = players[5].id;
  w.commit(
    'Update players',
    w.event.copy(
      players: [
        for (final p in w.event.players)
          p.id == withdrawn
              ? p.copy(withdrawn: true, notes: 'Left after round 2 (sample)')
              : p.id == bye
              ? p.copy(byes: {4: 1})
              : p,
      ],
    ),
  );
  final open = Section(
    id: _id(),
    name: 'Open',
    players: [for (final p in players.take(16)) p.id],
    plannedRounds: 4,
  );
  final reserve = Section(
    id: _id(),
    name: 'U1800',
    players: [for (final p in players.skip(16)) p.id],
    plannedRounds: 4,
    boardStart: 20,
    ratingCeiling: 1800,
  );
  // Withdraw only after the sections are seeded so rounds 1–2 include them.
  final restored = [
    for (final p in w.event.players)
      p.id == withdrawn ? p.copy(withdrawn: false, notes: '') : p,
  ];
  w.commit(
    'Create sections',
    w.event.copy(players: restored, sections: [open, reserve]),
  );
  for (final round in [1, 2, 3]) {
    for (final s in [open.id, reserve.id]) {
      w.post(s);
      w.begin(s);
      w.play(s, leaveOpen: round == 3 ? {2, 5, 21, 24} : const {});
    }
    if (round == 2) {
      w.commit(
        'Withdraw player',
        w.event.copy(
          players: [
            for (final p in w.event.players)
              p.id == withdrawn
                  ? p.copy(
                      withdrawn: true,
                      notes: 'Left after round 2 (sample)',
                    )
                  : p,
          ],
        ),
      );
    }
  }
  w.close();
}

/// Sixteen players, four quads, every round played.
void _quadsFinished(String path) {
  final w = _Writer(path);
  w.start(
    Event(
      id: _id(),
      name: 'Saturday Quads (sample)',
      date: '2026-09-26',
      timeControl: 'G/30 d5',
      venue: 'Meow Chess Club',
      city: 'Cambridge',
      state: 'MA',
      practice: true,
    ),
  );
  w.commit(
    'Import players',
    w.event.copy(
      players: _roster('samples/sample_players.csv').take(16).toList(),
    ),
  );
  w.commit('Make quads', w.event.copy(sections: makeQuads(w.event, _id)));
  for (var round = 1; round <= 3; round++) {
    for (final s in w.event.sections.map((s) => s.id).toList()) {
      w.post(s);
      w.begin(s);
      w.play(s);
    }
  }
  w.close();
}
