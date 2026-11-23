import '../domain/fide.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart' show TimeControl;

/// A round's games as PGN headers with no moves: one game per board, ready
/// for whoever enters the scoresheets, or for boards that record the moves
/// themselves. A game without a result yet carries `*`, so the file can be
/// made as soon as the round is posted.
///
/// [sections] limits the file to those sections (all when null) and
/// [rounds] names the round of a section, by ID; a section without one
/// gives every posted round. Byes and forfeits are left out: no game was
/// played. Ladders and side games, whose rounds are not rounds, are too.
String pgnHeaders(
  Event event, {
  Iterable<String>? sections,
  Map<String, int> rounds = const {},
}) {
  final wanted = sections?.toSet();
  final games = <String>[];
  for (final s in event.sections) {
    if (wanted != null && !wanted.contains(s.id)) continue;
    if (!pgnExportable(s)) continue;
    final category = s.fideRated ? sectionFideCategory(event, s) : null;
    int rating(Player p) => s.fideRated ? fideRating(p, category) : p.rating;
    final control = _timeControl(s.effectiveTimeControl(event));
    for (final r in s.rounds) {
      if (rounds[s.id] case final only? when only != r.number) continue;
      final ordered = [...r.games]
        ..sort(
          (a, b) => a.board != b.board
              ? a.board.compareTo(b.board)
              : a.leg.compareTo(b.leg),
        );
      for (final g in ordered) {
        final result = _result(g.outcome);
        if (result == null) continue;
        final white = event.player(g.white), black = event.player(g.black);
        games.add(
          [
            _tag('Event', event.name),
            _tag('Site', _site(event)),
            _tag('Date', event.date.replaceAll('-', '.')),
            // A double round's two games are 3.1 and 3.2.
            _tag(
              'Round',
              s.doubleGames ? '${r.number}.${g.leg}' : '${r.number}',
            ),
            _tag('White', white.name),
            _tag('Black', black.name),
            _tag('Result', result),
            _tag('Section', s.name),
            _tag('Board', '${g.board}'),
            if (rating(white) > 0) _tag('WhiteElo', '${rating(white)}'),
            if (rating(black) > 0) _tag('BlackElo', '${rating(black)}'),
            if (white.title.isNotEmpty) _tag('WhiteTitle', white.title),
            if (black.title.isNotEmpty) _tag('BlackTitle', black.title),
            if (white.fideId.isNotEmpty) _tag('WhiteFideId', white.fideId),
            if (black.fideId.isNotEmpty) _tag('BlackFideId', black.fideId),
            if (control != null) _tag('TimeControl', control),
            '',
            result,
            '',
          ].join('\n'),
        );
      }
    }
  }
  if (games.isEmpty) {
    throw const TournamentException(
      'There are no games to write: no round is paired in what was chosen.',
    );
  }
  return games.join('\n');
}

/// Whether [s]'s rounds are games a scoresheet could record.
bool pgnExportable(Section s) =>
    s.format != Format.ladder && s.format != Format.bughouse && !s.sideGames;

/// The PGN result of a game, or null for a game that was never played.
String? _result(Outcome o) => switch (o) {
  Outcome.whiteWin => '1-0',
  Outcome.blackWin => '0-1',
  Outcome.draw => '1/2-1/2',
  Outcome.whiteForfeit || Outcome.blackForfeit || Outcome.doubleForfeit => null,
  // Still to be played, or scored in a way PGN has no word for.
  _ => '*',
};

String _site(Event e) {
  final place = [
    e.venue.trim(),
    e.city.trim(),
    e.state.trim(),
  ].where((part) => part.isNotEmpty).join(', ');
  return place.isEmpty ? '?' : place;
}

/// PGN's own notation (seconds): `3600` for G/60, `5400+30` with an
/// increment, `40/5400:1800` for two controls. PGN has no word for a
/// delay, so a delay is left out. Null when the control cannot be read.
String? _timeControl(String text) {
  final TimeControl control;
  try {
    control = TimeControl.parse(text);
  } on TournamentException {
    return null;
  }
  final bonus = control.bonusKind == 'inc' && control.bonusSeconds > 0
      ? '+${control.bonusSeconds}'
      : '';
  return [
    for (final (moves, minutes) in control.stages)
      '${moves == null ? '' : '$moves/'}${minutes * 60}$bonus',
  ].join(':');
}

/// One tag pair, with the two characters PGN escapes inside a string.
String _tag(String name, String value) =>
    '[$name "${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"]';
