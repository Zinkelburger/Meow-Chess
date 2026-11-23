import 'fixed_schedule.dart';
import 'model.dart';
import 'standings.dart';

/// What a scoreboard shows of the event: the choices the director makes in
/// the Scoreboard panel.
class ScoreboardSettings {
  const ScoreboardSettings({
    this.hidden = const {},
    this.pairings = true,
    this.standings = true,
    this.seconds = 10,
  });

  /// The sections left off the board, by ID. A section added later shows.
  final Set<String> hidden;
  final bool pairings, standings;

  /// How long each screen stays up.
  final int seconds;

  static const minSeconds = 3, maxSeconds = 120;

  ScoreboardSettings copy({
    Set<String>? hidden,
    bool? pairings,
    bool? standings,
    int? seconds,
  }) => ScoreboardSettings(
    hidden: hidden ?? this.hidden,
    pairings: pairings ?? this.pairings,
    standings: standings ?? this.standings,
    seconds: (seconds ?? this.seconds).clamp(minSeconds, maxSeconds),
  );

  Json toJson() => {
    'hidden': hidden.toList()..sort(),
    'pairings': pairings,
    'standings': standings,
    'seconds': seconds,
  };

  /// Reads saved settings; anything missing or malformed keeps its default.
  factory ScoreboardSettings.fromJson(Json j) => ScoreboardSettings(
    hidden: {
      if (j['hidden'] case final List<dynamic> ids) ...ids.whereType<String>(),
    },
    pairings: j['pairings'] is bool ? j['pairings'] as bool : true,
    standings: j['standings'] is bool ? j['standings'] as bool : true,
    seconds: (j['seconds'] is int ? j['seconds'] as int : 10).clamp(
      minSeconds,
      maxSeconds,
    ),
  );
}

/// One table of the scoreboard: a round's pairings or a section's
/// standings. The page splits long tables across screens.
class ScoreboardTable {
  const ScoreboardTable({
    required this.section,
    required this.title,
    required this.kind,
    required this.columns,
    required this.rows,
    this.notes = const [],
  });
  final String section, title;

  /// `pairings` or `standings`: how the page lays the columns out.
  final String kind;
  final List<String> columns;
  final List<List<String>> rows;

  /// Lines under the table: the round's byes.
  final List<String> notes;

  Json toJson() => {
    'section': section,
    'title': title,
    'kind': kind,
    'columns': columns,
    'rows': rows,
    if (notes.isNotEmpty) 'notes': notes,
  };
}

/// The round a section's board shows. A Swiss shows its latest round, so a
/// long game from an earlier round does not pull the screen back; a fixed
/// schedule, posted whole, shows the first round still being played.
Round? scoreboardRound(Section s) {
  if (s.rounds.isEmpty) return null;
  if (hasFixedSchedule(s)) {
    return s.rounds.where((r) => !r.complete).firstOrNull ?? s.rounds.last;
  }
  return s.rounds.last;
}

String _result(Outcome o) => switch (o) {
  Outcome.unreported => '',
  Outcome.unfinished => 'playing',
  Outcome.disputed => 'disputed',
  _ => o.label,
};

/// [o] as the other side reads it: `1–0` for `0–1`.
Outcome _reversed(Outcome o) => switch (o) {
  Outcome.whiteWin => Outcome.blackWin,
  Outcome.blackWin => Outcome.whiteWin,
  Outcome.whiteForfeit => Outcome.blackForfeit,
  Outcome.blackForfeit => Outcome.whiteForfeit,
  Outcome.whiteHalf => Outcome.blackHalf,
  Outcome.blackHalf => Outcome.whiteHalf,
  _ => o,
};

String _byeLabel(Section s, ByeAward b) {
  final full = s.doubleGames ? 4 : 2;
  return b.points == full
      ? 'full-point bye'
      : b.points == 0
      ? 'no game'
      : '${scoreText(b.points)}-point bye';
}

/// The tables a scoreboard shows for [event], section by section in event
/// order: each section's current pairings, then its standings once a round
/// is complete. Only what is posted on the wall appears: names, boards,
/// results, ratings and scores. Never an ID, a note or a contact detail.
List<ScoreboardTable> scoreboardTables(
  Event event,
  ScoreboardSettings settings,
) {
  final tables = <ScoreboardTable>[];
  String name(String id) => event.player(id).name;
  for (final s in event.sections) {
    if (settings.hidden.contains(s.id) || s.sideGames) continue;
    final round = scoreboardRound(s);
    if (settings.pairings && round != null && s.format != Format.ladder) {
      String side(String id, String partner) =>
          partner.isEmpty ? name(id) : '${name(id)} & ${name(partner)}';
      final firstLegs = [
        for (final g in round.games)
          if (g.leg == 1) g,
      ]..sort((a, b) => a.board.compareTo(b.board));
      tables.add(
        ScoreboardTable(
          section: s.name,
          title: 'Round ${round.number} pairings',
          kind: 'pairings',
          columns: const ['Board', 'White', 'Result', 'Black'],
          rows: [
            for (final g in firstLegs)
              [
                '${g.board}',
                side(g.white, g.whitePartner),
                [
                  _result(g.outcome),
                  // A double round's second game, read from the same side.
                  for (final second in round.games)
                    if (second.leg != 1 && second.board == g.board)
                      _result(
                        second.white == g.white
                            ? second.outcome
                            : _reversed(second.outcome),
                      ),
                ].where((r) => r.isNotEmpty).join(', '),
                side(g.black, g.blackPartner),
              ],
          ],
          notes: [
            if (round.byes.isNotEmpty)
              'Byes: ${[for (final b in round.byes) '${name(b.player)} (${_byeLabel(s, b)})'].join(', ')}',
          ],
        ),
      );
    }
    // A knockout places by its bracket and a ladder by its list; neither
    // has a score table to show.
    final complete = s.rounds.where((r) => r.complete).length;
    if (settings.standings &&
        complete > 0 &&
        !const [Format.knockout, Format.ladder].contains(s.format)) {
      tables.add(
        ScoreboardTable(
          section: s.name,
          title: s.rounds.every((r) => r.complete) && s.finished
              ? 'Final standings'
              : 'Standings',
          kind: 'standings',
          columns: const ['Place', 'Player', 'Rating', 'Score'],
          rows: [
            for (final row in standings(event, s))
              [
                '${row.rank}',
                row.player.name,
                row.player.rating == 0 ? 'unr.' : '${row.player.rating}',
                scoreText(row.points),
              ],
          ],
        ),
      );
    }
  }
  return tables;
}
