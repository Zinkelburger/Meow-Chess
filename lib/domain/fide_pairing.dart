import '../engine/bbp_pairings.dart';
import 'model.dart';
import 'swiss_pairing.dart';
import 'trf.dart';

/// Policy recorded on rounds paired by the FIDE Dutch system.
const fideDutchPolicy = 'fide-dutch-2026-bbp-6';

/// The in-tournament TRF26 file BBP Pairings reads to pair round [n] of
/// [section]: the rounds before it (pairing assumptions, and adjourned
/// games as draws, standing in for missing results), and [byes] plus any
/// house player as those not paired.
String fideEngineInput(
  Event event,
  Section section,
  int n,
  List<ByeAward> byes, {
  TrfTournament? tournament,
}) => writeTrf(
  event,
  section,
  pairRound: n,
  outcomeOf: (g) =>
      g.outcome.resolved ? g.outcome : g.pairingAssumption ?? g.outcome,
  sittingOut: {
    for (final b in byes) b.player: b.points,
    // FIDE pairs an odd field with the pairing-allocated bye, never a
    // house player.
    for (final id in section.players)
      if (event.player(id).house && !byes.any((b) => b.player == id)) id: 0,
  },
  initialColor: effectiveColorToss(event) == 'higherBlack' ? 'B' : 'W',
  tournament: tournament,
);

/// C.04.3, the FIDE Dutch system (rules effective 1 February 2026), for
/// round [n] of a FIDE-rated Swiss [section]. The section is written as an
/// in-tournament TRF26 file and paired by BBP Pairings; [available] and
/// [byes] come from `roundAvailability`, so requested byes and withdrawals
/// are already settled. The pairing-allocated bye scores the section's
/// [Section.pabPoints] (a win unless announced otherwise, C.04.1 3); an
/// adjourned game counts as a draw (C.04.2 3.1).
SwissProposal pairFideDutch(
  Event event,
  Section section,
  int n,
  List<ByeAward> byes,
) {
  // validateEvent keeps a FIDE Swiss to one game per round and the Baku
  // acceleration at most.
  final t = trfTournament(event, section);
  final trf = fideEngineInput(event, section, n, byes, tournament: t);
  final List<(int, int)> pairs;
  try {
    pairs = bbpPairDutch(trf);
  } on BbpFailure catch (e) {
    throw TournamentException(switch (e.kind) {
      BbpFailureKind.noValidPairing =>
        'The FIDE Dutch system finds no legal pairing for round $n: every arrangement repeats a game or breaks an absolute colour rule. Pair this round by hand.',
      BbpFailureKind.tooLarge =>
        'The section is too large for the FIDE pairing engine.',
      _ => 'The FIDE pairing engine could not read this section: ${e.message}',
    });
  }
  final games = <(String, String)>[];
  final awarded = [
    ...byes,
    // FIDE pairs an odd field with the pairing-allocated bye, never a
    // house player.
    for (final id in section.players)
      if (event.player(id).house &&
          !event.player(id).withdrawn &&
          !byes.any((b) => b.player == id))
        ByeAward(id, 0, 'House player not needed'),
  ];
  for (final (white, black) in pairs) {
    final w = t.players[white - 1].id;
    if (black == 0) {
      awarded.add(
        ByeAward(
          w,
          section.pabPoints,
          'Pairing-allocated bye',
          allocated: true,
        ),
      );
    } else {
      games.add((w, t.players[black - 1].id));
    }
  }
  final restricted = section.players.any(
    (id) => event.player(id).avoid.any(section.players.contains),
  );
  return SwissProposal(games, awarded, [
    'Paired by the FIDE Dutch system (C.04.3, 2026 rules) with BBP Pairings, from pairing numbers ranked by ${t.section.fideRanking.isEmpty ? 'the section default' : t.section.fideRanking}.',
    if (section.accelerated == 'baku' && n <= (section.plannedRounds + 1) ~/ 2)
      'Baku acceleration (C.04.7): group A pairs with ${n <= ((section.plannedRounds + 1) ~/ 2 + 1) ~/ 2 ? 'one virtual point' : 'half a virtual point'} this round.',
    if (section.pabPoints != 2)
      'The pairing-allocated bye scores ${section.pabPoints == 1 ? 'a draw' : 'nothing'}, as announced.',
    if (restricted && n >= 3)
      'Do-not-pair requests are still in force. They are not part of the FIDE Dutch rules; FIDE expects them only in early rounds, so consider removing them.',
    if (section.rounds.any(
      (r) => r.games.any((g) => g.outcome == Outcome.unfinished),
    ))
      'An adjourned game counts as a draw for this pairing only (C.04.2 3.1).',
  ]);
}
