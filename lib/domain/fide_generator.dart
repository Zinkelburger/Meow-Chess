import 'dart:math';

import 'fide.dart';
import 'fide_tiebreaks.dart';
import 'model.dart';
import 'pairing.dart';
import 'trf.dart';

/// What a simulated FIDE tournament looks like: the Random Tournament
/// Generator (RTG) the FIDE Technical Commission asks of a tournament
/// program (C.02.03 7.2.4; TEC Manual 3.9.4).
class RandomTournamentSettings {
  const RandomTournamentSettings({
    this.players = 30,
    this.rounds = 9,
    this.seed = 0,
    this.highestRating = 2600,
    this.lowestRating = 1400,
    this.unratedRate = 0,
    this.drawRate = 0.3,
    this.forfeitRate = 0.02,
    this.halfByeRate = 0.03,
    this.zeroByeRate = 0.01,
    this.fullByeRate = 0,
    this.withdrawRate = 0.01,
    this.lateEntryRate = 0,
    this.unusualRate = 0,
    this.shortGameRate = 0,
    this.baku = false,
    this.pabPoints = 2,
    this.tiebreaks = const ['BH/C1', 'BH', 'SB', 'DE', 'WIN'],
  });

  final int players, rounds, seed, highestRating, lowestRating;

  /// Shares of the field without a FIDE rating, and of games drawn when
  /// the players are equal (draws thin out as ratings part).
  final double unratedRate, drawRate;

  /// Per game: a forfeit (a tenth of them double forfeits), a ½–0, 0–½ or
  /// played 0–0 result, or a game that lasted less than one move.
  final double forfeitRate, unusualRate, shortGameRate;

  /// Per player and round: a requested half-, zero- or full-point bye, and
  /// a withdrawal after the round.
  final double halfByeRate, zeroByeRate, fullByeRate, withdrawRate;

  /// Share of the field entering after round 1 (in rounds 2–4).
  final double lateEntryRate;

  /// The Baku acceleration (C.04.7), and the pairing-allocated bye's value
  /// in half-points.
  final bool baku;
  final int pabPoints;

  /// The announced tie-break order (MTB26 codes, record 202).
  final List<String> tiebreaks;

  /// Problems with these settings, or null.
  String? get problem {
    if (players < 2 || players > 9999) return 'Players must be 2 to 9999.';
    if (rounds < 1 || rounds > 99) return 'Rounds must be 1 to 99.';
    if (lowestRating < 1000 || highestRating > 3000) {
      return 'Ratings must lie between 1000 and 3000.';
    }
    if (lowestRating > highestRating) {
      return 'The lowest rating is above the highest.';
    }
    if (!const {0, 1, 2}.contains(pabPoints)) {
      return 'The pairing-allocated bye scores 0, ½ or 1.';
    }
    for (final rate in [
      unratedRate,
      drawRate,
      forfeitRate,
      unusualRate,
      shortGameRate,
      halfByeRate,
      zeroByeRate,
      fullByeRate,
      withdrawRate,
      lateEntryRate,
    ]) {
      if (rate < 0 || rate > 1) return 'Rates are between 0 and 1.';
    }
    if (fideTiebreakCodesProblem(tiebreaks) case final p?) return p;
    return null;
  }
}

/// A simulated FIDE-rated Swiss, paired round by round through the same
/// path as the app (`proposeRound`, so the FIDE Dutch system by BBP
/// Pairings), with results drawn from the FIDE rating table (B.02 8.1.2):
/// a player's expected score sets their chance of winning, less half the
/// chance of a draw. Returns the event; [writeTrf] gives its TRF26 report.
Event generateFideTournament(RandomTournamentSettings s) {
  if (s.problem case final p?) throw TournamentException(p);
  final rng = Random(s.seed);
  final spread = s.highestRating - s.lowestRating;
  final players = [
    for (var i = 0; i < s.players; i++)
      Player(
        id: 'p${i + 1}',
        name: 'First${i + 1} Last${i + 1}',
        fideId: '${1000000 + i + 1}',
        fideStandard: rng.nextDouble() < s.unratedRate
            ? 0
            : s.lowestRating + (spread == 0 ? 0 : rng.nextInt(spread + 1)),
        sex: rng.nextBool() ? 'm' : 'w',
        federation: 'USA',
      ),
  ];
  // Late entries join in rounds 2–4; the rest are there from round 1.
  final joins = <String, int>{
    for (final p in players)
      p.id: s.rounds > 1 && rng.nextDouble() < s.lateEntryRate
          ? 2 + rng.nextInt(min(3, s.rounds - 1))
          : 1,
  };
  var event = Event(
    id: 'rtg-${s.seed}',
    name: 'Random tournament ${s.seed}',
    date: '2026-03-01',
    endDate: '2026-03-0${min(9, 1 + s.rounds ~/ 2)}',
    city: 'Simulation',
    timeControl: 'G/90 inc/30',
    colorToss: rng.nextBool() ? 'higherWhite' : 'higherBlack',
    fide: const FideRegistration(
      chiefArbiter: FideOfficial(name: 'Random Generator'),
    ),
    fideTiebreaks: s.tiebreaks,
    players: players,
    sections: [
      Section(
        id: 'open',
        name: 'Open',
        players: [
          for (final p in players)
            if (joins[p.id] == 1) p.id,
        ],
        plannedRounds: s.rounds,
        fideRated: true,
        // FIDE only, so ½–0, 0–½ and a played 0–0 may occur.
        unrated: true,
        accelerated: s.baku ? 'baku' : '',
        pabPoints: s.pabPoints,
      ),
    ],
  );
  var games = 0;
  for (var n = 1; n <= s.rounds; n++) {
    var section = event.sections.single;
    // Entries joining this round, and requested byes for it.
    final entering = [
      for (final p in players)
        if (joins[p.id] == n && n > 1) p.id,
    ];
    final updated = <Player>[];
    for (final p in event.players) {
      final active =
          (section.players.contains(p.id) || entering.contains(p.id)) &&
          !p.withdrawn;
      final roll = rng.nextDouble();
      final bye = !active
          ? null
          : roll < s.halfByeRate
          ? 1
          : roll < s.halfByeRate + s.zeroByeRate
          ? 0
          : roll < s.halfByeRate + s.zeroByeRate + s.fullByeRate
          ? 2
          : null;
      updated.add(bye == null ? p : p.copy(byes: {...p.byes, n: bye}));
    }
    section = section.copy(players: [...section.players, ...entering]);
    event = event.copy(players: updated, sections: [section]);
    final round = proposeRound(event, section, () => 'g${++games}');
    final played = round.copy(
      games: [for (final g in round.games) _play(event, g, rng, s)],
    );
    section = section.copy(rounds: [...section.rounds, played]);
    // C.04.2: pairing numbers are fixed once round 1 is paired.
    if (n == 1) {
      final before = event.sections.single;
      section = section.copy(
        fideOrder: [for (final p in fidePairingOrder(event, before)) p.id],
        bakuLast: bakuGroupLast(event, before) ?? '',
      );
    }
    final withdrawing = {
      if (n < s.rounds)
        for (final id in section.players)
          if (rng.nextDouble() < s.withdrawRate) id,
    };
    event = event.copy(
      players: [
        for (final p in event.players)
          withdrawing.contains(p.id) ? p.copy(withdrawn: true) : p,
      ],
      sections: [section],
    );
  }
  validateEvent(event);
  return event;
}

Game _play(Event event, Game g, Random rng, RandomTournamentSettings s) {
  final roll = rng.nextDouble();
  if (roll < s.forfeitRate) {
    final f = rng.nextDouble();
    return g.copy(
      outcome: f < 0.1
          ? Outcome.doubleForfeit
          : f < 0.55
          ? Outcome.whiteForfeit
          : Outcome.blackForfeit,
    );
  }
  if (roll < s.forfeitRate + s.unusualRate) {
    return g.copy(
      outcome: const [
        Outcome.whiteHalf,
        Outcome.blackHalf,
        Outcome.bothLose,
      ][rng.nextInt(3)],
    );
  }
  // An unrated player plays at the bottom of the rating range.
  int rating(String id) {
    final r = event.player(id).fideStandard;
    return r > 0 ? r : 1000;
  }

  final expected =
      fideExpectedHundredths(rating(g.white) - rating(g.black)) / 100;
  final draw = min(s.drawRate, 2 * min(expected, 1 - expected));
  final r = rng.nextDouble();
  final outcome = r < expected - draw / 2
      ? Outcome.whiteWin
      : r < expected + draw / 2
      ? Outcome.draw
      : Outcome.blackWin;
  return g.copy(
    outcome: outcome,
    shortGame: rng.nextDouble() < s.shortGameRate,
  );
}
