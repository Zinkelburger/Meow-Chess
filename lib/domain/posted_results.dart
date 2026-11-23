/// Results a club's website shows for a round, as players enter them there,
/// and what they mean for this event.
///
/// The website is taken at its word only where it is plainly showing this
/// event's round: the section and round number agree, and every board it
/// lists has the same two players with the same colors as a board here.
/// One board that differs means the page shows other pairings (last week's
/// event, or a round paired again since), so nothing is taken from that
/// round. A result entered here by the director is never replaced by the
/// website's; the two are listed side by side.
///
/// Once the section's next round is paired, the website no longer changes
/// a round at all: not a missing result, not a correction. Pairings were
/// made from the results as they stood, so any change there is the
/// director's to enter, and the board is listed for them.
library;

import 'model.dart';
import 'us_chess.dart';

/// One board as the website lists it. The result cells are kept as shown.
class PostedGame {
  const PostedGame({
    required this.white,
    required this.black,
    this.board,
    this.whiteResult = '',
    this.blackResult = '',
  });
  final String white, black, whiteResult, blackResult;
  final int? board;

  /// What the two cells say, or null when they are empty, cleared, or say
  /// something with no equivalent here ([understood] tells which).
  Outcome? get outcome => postedOutcome(whiteResult, blackResult);

  /// Whether the website shows a result at all.
  bool get hasResult =>
      _cell(whiteResult) != (null, '') || _cell(blackResult) != (null, '');

  /// False for a result this app has no equivalent of, such as a forfeit
  /// draw, or one it cannot read.
  bool get understood => !hasResult || outcome != null;

  /// The two cells as the website shows them, for a message.
  String get shown => '${whiteResult.trim()}–${blackResult.trim()}';
}

/// One section's round as the website lists it.
class PostedRound {
  const PostedRound({
    required this.section,
    required this.round,
    required this.games,
  });
  final String section;
  final int round;
  final List<PostedGame> games;
}

/// A result cell as (half-points, suffix letter): `1` is (2, ''), `½` is
/// (1, ''), `0F` is (0, 'F'). Empty and cleared (`U`) cells are (null, '');
/// an unreadable one is (null, '?').
(int?, String) _cell(String text) {
  final t = text
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('&frac12;', '½')
      .toUpperCase();
  if (t.isEmpty) return (null, '');
  final m = RegExp(
    r'^(1/2|½|0?\.5|1(?:\.0)?|0(?:\.0)?)([XFZU]?)$',
  ).firstMatch(t);
  if (m == null) return (null, '?');
  if (m[2] == 'U') return (null, '');
  final points = switch (m[1]!) {
    '1' || '1.0' => 2,
    '0' || '0.0' => 0,
    _ => 1,
  };
  return (points, m[2]!);
}

/// The result two cells of a website's pairing table state, or null when
/// they state none or one this app cannot enter (a forfeit draw, a played
/// game that does not add up to one point).
Outcome? postedOutcome(String white, String black) {
  final (w, wLetter) = _cell(white);
  final (b, bLetter) = _cell(black);
  if (w == null || b == null) return null;
  if (wLetter == 'Z' || bLetter == 'Z') return null;
  final forfeit = wLetter.isNotEmpty || bLetter.isNotEmpty;
  return switch ((w, b)) {
    (2, 0) => forfeit ? Outcome.whiteForfeit : Outcome.whiteWin,
    (0, 2) => forfeit ? Outcome.blackForfeit : Outcome.blackWin,
    (1, 1) => forfeit ? null : Outcome.draw,
    (0, 0) => forfeit ? Outcome.doubleForfeit : null,
    _ => null,
  };
}

/// A name as a set of words, so `Winter, Shea` and `Shea Winter` are the
/// same person and accents and capitals do not matter.
String personKey(String name) {
  final words =
      nameKey(
          name,
        ).split(RegExp(r"[^a-z0-9À-ɏ']+")).where((w) => w.isNotEmpty).toList()
        ..sort();
  return words.join(' ');
}

/// A section name as a website carries it: SwissSys file names lose
/// punctuation, so only letters and digits are compared.
String _sectionKey(String name) =>
    nameKey(name).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// A board where the website and this event disagree, or where the
/// website's result needs the director.
class PostedDifference {
  const PostedDifference({
    required this.gameId,
    required this.section,
    required this.round,
    required this.board,
    required this.white,
    required this.black,
    required this.here,
    required this.shown,
    this.website,
    this.why = '',
    this.byHand = false,
  });
  final String gameId, section, white, black;
  final int round, board;

  /// The result this event holds.
  final Outcome here;

  /// The website's result when this app can enter it; null when it cannot.
  final Outcome? website;

  /// The website's result as it shows it.
  final String shown;

  /// Why the result was not entered by itself, when [describe] should say.
  final String why;

  /// True when the director has to enter this result on the board
  /// themselves (a later round is paired), so it offers no Use button.
  final bool byHand;

  String describe({required bool nameSection}) {
    final where =
        '${nameSection ? '$section ' : ''}board $board, $white – $black';
    final says = website?.label ?? shown;
    if (website == null) {
      return '$where: the website says $says, which cannot be entered '
          'from here. Enter the result yourself.';
    }
    if (why.isNotEmpty) return '$where: the website says $says. $why';
    return here.resolved
        ? '$where: the website says $says, entered here as ${here.label}.'
        : '$where: the website says $says, not entered here.';
  }
}

/// What a reading of the website means for the event.
class PostedReading {
  const PostedReading({
    this.take = const {},
    this.corrections = const {},
    this.differences = const [],
    this.problems = const [],
    this.following = const [],
  });

  /// Results to enter: boards waiting for one that the website now has.
  final Map<String, Outcome> take;

  /// Boards whose result came from the website and has since changed there.
  final Map<String, Outcome> corrections;
  final List<PostedDifference> differences;

  /// Why a round is not being followed, in the director's words.
  final List<String> problems;

  /// The rounds whose results are being taken, as `Open round 1`.
  final List<String> following;
}

/// Compares what the website [posted] with [event] (with its unposted quad
/// rounds projected). [taken] is what this app has already entered from
/// the website, by game: a result of this app's own entering follows the
/// website when it is corrected there, and one the director has since
/// cleared or undone is not entered again. [held] are boards the event
/// refused to take a result for; they are listed for the director instead.
/// [settled] are games a later round was paired after (see
/// [settledGames]): the website changes none of them, and each board where
/// it differs is listed for the director to enter by hand.
PostedReading readPostedResults(
  Event event,
  List<PostedRound> posted, {
  Map<String, Outcome> taken = const {},
  Set<String> held = const {},
  Set<String> settled = const {},
}) {
  final take = <String, Outcome>{}, corrections = <String, Outcome>{};
  final differences = <PostedDifference>[];
  final problems = <String>[], following = <String>[];

  for (final s in event.sections) {
    if (s.rounds.isEmpty || s.format == Format.ladder) continue;
    final waiting = s.rounds.where((r) => !r.complete).firstOrNull;
    final named = posted
        .where((p) => _sectionKey(p.section) == _sectionKey(s.name))
        .toList();
    // A website that names its sections differently is still followed
    // where a round's boards are exactly this section's.
    final candidates = named.isNotEmpty
        ? named
        : [
            for (final p in posted)
              if (s.rounds.where((r) => r.number == p.round).firstOrNull
                  case final r? when _sameBoards(event, r, p))
                p,
          ];
    final listed = candidates.where((p) => p.games.isNotEmpty).toList();
    if (listed.isEmpty) {
      if (waiting != null) {
        problems.add(
          '${s.name} round ${waiting.number} is not on the website yet.',
        );
      }
      continue;
    }
    for (final page in listed) {
      final round = s.rounds.where((r) => r.number == page.round).firstOrNull;
      if (round == null) {
        problems.add(
          'The website shows ${s.name} round ${page.round}, which this '
          'event does not have.',
        );
        continue;
      }
      final byPlayers = <(String, String), List<Game>>{};
      for (final g in round.games) {
        (byPlayers[(
                  personKey(event.player(g.white).name),
                  personKey(event.player(g.black).name),
                )] ??=
                [])
            .add(g);
      }
      final matched = <(PostedGame, Game)>[];
      PostedGame? stranger;
      for (final p in page.games) {
        final games = byPlayers[(personKey(p.white), personKey(p.black))];
        // Two games between the same players with the same colors cannot
        // be told apart, so neither is touched.
        if (games == null || games.length != 1) {
          stranger ??= p;
        } else {
          matched.add((p, games.single));
        }
      }
      if (stranger != null) {
        problems.add(
          '${s.name} round ${page.round}: the website has other pairings '
          '(${stranger.board == null ? '' : 'board ${stranger.board}, '}'
          '${stranger.white} – ${stranger.black}), so nothing is taken from '
          'it. If pairings changed here, send them to the website again.',
        );
        continue;
      }
      if (!round.games.every((g) => settled.contains(g.id))) {
        following.add('${s.name} round ${page.round}');
      }
      for (final (p, g) in matched) {
        if (!p.hasResult) continue;
        final website = p.outcome;
        if (website == g.outcome) continue;
        PostedDifference difference({String why = '', bool byHand = false}) =>
            PostedDifference(
              gameId: g.id,
              section: s.name,
              round: round.number,
              board: g.board,
              white: event.player(g.white).name,
              black: event.player(g.black).name,
              here: g.outcome,
              website: website,
              shown: p.shown,
              why: why,
              byHand: byHand,
            );
        if (settled.contains(g.id)) {
          // Pairings have moved on: the website no longer changes this
          // round, so a result it shows that differs is the director's.
          if (website != null) {
            differences.add(
              difference(
                byHand: true,
                why:
                    'A later round is paired, so the website no longer '
                    'changes this one. Enter it yourself if it is right.',
              ),
            );
          } else if (!g.outcome.resolved) {
            differences.add(difference());
          }
        } else if (website == null) {
          // A result the website has and this app cannot enter matters
          // only while the board still waits for one.
          if (!g.outcome.resolved) differences.add(difference());
        } else if (g.outcome == Outcome.disputed) {
          differences.add(difference(why: 'The game is marked disputed here.'));
        } else if (!g.outcome.resolved) {
          if (taken[g.id] == website) {
            differences.add(
              difference(
                why:
                    'It was entered from the website and then taken back here.',
              ),
            );
          } else if (held.contains(g.id)) {
            // Refused because a later round is paired: the website no
            // longer changes it, so the director enters it by hand.
            differences.add(
              difference(
                byHand: true,
                why:
                    'A later round was paired without it. Enter it yourself '
                    'if it is right.',
              ),
            );
          } else {
            take[g.id] = website;
          }
        } else if (taken[g.id] == g.outcome) {
          corrections[g.id] = website;
        } else {
          differences.add(difference());
        }
      }
      if (waiting?.number == round.number) {
        final shownGames = {for (final (_, g) in matched) g.id};
        final absent = [
          for (final g in round.games)
            if (!shownGames.contains(g.id) && !g.outcome.resolved) g.board,
        ];
        if (absent.isNotEmpty) {
          problems.add(
            '${s.name} round ${round.number}: '
            '${absent.length == 1 ? 'board ${absent.single} is' : 'boards ${absent.join(', ')} are'} '
            'not on the website.',
          );
        }
      }
    }
    if (waiting != null && !listed.any((p) => p.round == waiting.number)) {
      problems.add(
        '${s.name} round ${waiting.number} is not on the website yet '
        '(it shows round ${listed.map((p) => p.round).join(', ')}).',
      );
    }
  }
  return PostedReading(
    take: take,
    corrections: corrections,
    differences: differences,
    problems: problems,
    following: following,
  );
}

/// Whether [page] lists boards, and each is a board of [round] with the
/// same colors.
bool _sameBoards(Event event, Round round, PostedRound page) {
  if (page.games.isEmpty) return false;
  final here = {
    for (final g in round.games)
      (
        personKey(event.player(g.white).name),
        personKey(event.player(g.black).name),
      ),
  };
  return page.games.every(
    (p) => here.contains((personKey(p.white), personKey(p.black))),
  );
}

/// Games the website may no longer change: those of every round a later
/// round of the same section was paired after, and those whose result a
/// player transfer carried into another section ([dependsOn], for games of
/// a section's latest round). [event] is the event as stored, without
/// projected quad rounds, so a round counts as paired only once posted.
Set<String> settledGames(Event event, {bool Function(String id)? dependsOn}) {
  final settled = <String>{};
  for (final s in event.sections) {
    final last = s.rounds.map((r) => r.number).fold(0, (a, b) => a > b ? a : b);
    for (final r in s.rounds) {
      for (final g in r.games) {
        if (r.number < last || (dependsOn?.call(g.id) ?? false)) {
          settled.add(g.id);
        }
      }
    }
  }
  return settled;
}
