import 'model.dart';
import 'swiss_pairing.dart';

/// Bughouse: two-player partnerships paired as a Swiss on match score.
///
/// The unit is the partnership ([Section.partners]). Each posted [Game] is
/// one partnership match: [Game.white] and [Game.black] sit on board 1,
/// their partners ([Game.whitePartner], [Game.blackPartner]) take the
/// opposite colors on board 2, and the one outcome is the match result.
/// Standings credit both partners with the match points, so a partnership
/// is always level. Bughouse is never US Chess rated (Scholastic
/// Regulations App. B; chapter 10 3B), so the section is unrated and the
/// rating report leaves it out.
const bughousePolicy = 'bughouse-swiss-v1';

/// The partnership [id] belongs to, or null when the player has none.
List<String>? partnershipOf(Section section, String id) =>
    section.partners.where((p) => p.contains(id)).firstOrNull;

/// The partner of [id], or empty when the player has none.
String partnerOf(Section section, String id) =>
    partnershipOf(section, id)?.where((x) => x != id).firstOrNull ?? '';

/// Players of [section] who are not in any partnership.
List<String> unpartnered(Section section) {
  final partnered = {for (final p in section.partners) ...p};
  return section.players.where((id) => !partnered.contains(id)).toList();
}

/// "Chen / Patel": the partnership's two names in listed order, or the one
/// name when [id] has no partner.
String partnershipName(Event event, Section section, String id) =>
    (partnershipOf(section, id) ?? [id])
        .map((x) => event.player(x).name)
        .join(' / ');

/// The pairing rating of a partnership: the average of its rated partners
/// (a partner without a rating does not drag the pair to half strength);
/// zero when neither is rated.
int partnershipRating(Event event, List<String> pair) {
  final rated = pair
      .map((id) => event.player(id).effectivePairingRating)
      .where((r) => r > 0)
      .toList();
  return rated.isEmpty ? 0 : rated.fold(0, (sum, r) => sum + r) ~/ rated.length;
}

/// The partner who stands for the pair in the Swiss engine: the higher
/// rated, then the first listed.
String representativeOf(Event event, List<String> pair) {
  final a = event.player(pair[0]), b = event.player(pair[1]);
  return b.effectivePairingRating > a.effectivePairingRating ? b.id : a.id;
}

/// Round [n] of a bughouse section: a Swiss on match score over the
/// partnerships, expanded into one match per board (two with colors
/// swapped when the section plays double games).
Round bughouseRound(Event event, Section section, int n, String Function() id) {
  if (section.partners.isEmpty) {
    throw const TournamentException(
      'Pair everyone up first: a bughouse section pairs partnerships, not players.',
    );
  }
  final byes = <ByeAward>[];
  for (final pid in unpartnered(section)) {
    byes.add(ByeAward(pid, 0, 'No partner'));
  }

  // One representative per partnership stands in for it: the higher-rated
  // partner, carrying the pair's average rating, both partners' bye
  // requests and both partners' do-not-pair requests.
  final repOf = <String, String>{};
  for (final pair in section.partners) {
    final rep = representativeOf(event, pair);
    for (final pid in pair) {
      repOf[pid] = rep;
    }
  }
  final representatives = <Player>[];
  final available = <String>[];
  for (final pair in section.partners) {
    final a = event.player(pair[0]), b = event.player(pair[1]);
    final rep = repOf[a.id]!;
    final rating = partnershipRating(event, pair);
    representatives.add(
      Player.fromJson({
        ...event.player(rep).toJson(),
        // The engine ranks by effectivePairingRating; a pair with no rated
        // partner stays unrated for 28L2 and 29D1c.
        'pairingRating': rating,
        'byes': {...a.byes, ...b.byes}.map((k, v) => MapEntry('$k', v)),
        'avoid': [
          for (final x in {...a.avoid, ...b.avoid}) repOf[x] ?? x,
        ],
        'withdrawn': false,
      }),
    );
    if (a.withdrawn || b.withdrawn) {
      for (final p in [a, b]) {
        byes.add(
          ByeAward(p.id, 0, p.withdrawn ? 'Withdrawn' : 'Partner withdrawn'),
        );
      }
      continue;
    }
    final requested = a.byes[n] ?? b.byes[n];
    if (requested != null) {
      for (final p in [a, b]) {
        byes.add(
          ByeAward(
            p.id,
            requested,
            p.byes.containsKey(n) ? 'Requested bye' : "Partner's requested bye",
          ),
        );
      }
      continue;
    }
    available.add(rep);
  }

  // The partnership's history as the representative's: every match the
  // pair played and every bye it took, deduplicated to one card.
  final rounds = <Round>[
    for (final r in section.rounds)
      r.copy(
        games: [
          for (final g in r.games)
            if (repOf.containsKey(g.white) && repOf.containsKey(g.black))
              Game(
                id: g.id,
                white: repOf[g.white]!,
                black: repOf[g.black]!,
                board: g.board,
                leg: g.leg,
                outcome: g.outcome,
                pairingAssumption: g.pairingAssumption,
                pairingReason: g.pairingReason,
              ),
        ],
        byes: () {
          final seen = <String>{};
          return [
            for (final b in r.byes)
              if (repOf[b.player] case final rep? when seen.add(rep))
                ByeAward(rep, b.points, b.reason, allocated: b.allocated),
          ];
        }(),
      ),
  ];
  final ranked = [...section.partners]
    ..sort((x, y) {
      final c = partnershipRating(
        event,
        y,
      ).compareTo(partnershipRating(event, x));
      return c != 0 ? c : repOf[x[0]]!.compareTo(repOf[y[0]]!);
    });
  final stand = section.copy(
    players: [for (final pair in ranked) repOf[pair[0]]!],
    format: Format.swiss,
    doubleGames: false,
    partners: const [],
    rounds: rounds,
  );
  final proposal = pairSwiss(
    event.copy(players: representatives, sections: [stand]),
    stand,
    n,
    available,
    const [],
  );

  final games = <Game>[];
  var board = section.boardStart;
  for (final (white, black) in proposal.games) {
    final wp = partnerOf(section, white), bp = partnerOf(section, black);
    games.add(
      Game(
        id: id(),
        white: white,
        black: black,
        board: board,
        whitePartner: wp,
        blackPartner: bp,
      ),
    );
    if (section.doubleGames) {
      games.add(
        Game(
          id: id(),
          white: black,
          black: white,
          board: board,
          leg: 2,
          whitePartner: bp,
          blackPartner: wp,
        ),
      );
    }
    board++;
  }
  for (final b in proposal.byes) {
    final points = b.allocated && section.doubleGames ? 4 : b.points;
    for (final pid in partnershipOf(section, b.player) ?? [b.player]) {
      byes.add(ByeAward(pid, points, b.reason, allocated: b.allocated));
    }
  }

  // The engine explains itself in the representatives' names; the director
  // reads partnerships.
  final names = [
    for (final rep in representatives)
      (event.player(rep.id).name, partnershipName(event, section, rep.id)),
  ]..sort((x, y) => y.$1.length.compareTo(x.$1.length));
  final explanations = [
    for (var line in proposal.explanations)
      () {
        for (final (from, to) in names) {
          if (from.isNotEmpty) line = line.replaceAll(from, to);
        }
        return line;
      }(),
  ];
  return Round(
    number: n,
    games: games,
    byes: byes,
    explanations: explanations,
    policy: bughousePolicy,
  );
}
