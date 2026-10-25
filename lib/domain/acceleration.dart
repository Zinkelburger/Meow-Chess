import 'model.dart';

/// Builds an explicit, frozen schedule from the current section roster.
/// This simple virtual-point method is not FIDE Baku or a certified US Chess
/// accelerated-pairing algorithm. It uses the existing Swiss pilot afterwards.
Map<String, List<int>> topHalfAcceleration(
  Event event,
  Section section, {
  required int rounds,
}) {
  if (section.format != Format.swiss || section.rounds.isNotEmpty) {
    throw const TournamentException(
      'Set acceleration on a Swiss section before posting round one.',
    );
  }
  if (rounds < 1 || rounds >= section.plannedRounds) {
    throw const TournamentException(
      'Leave at least one scheduled round without acceleration.',
    );
  }
  if (section.doubleGames ||
      section.scoring.win != 2 ||
      section.scoring.draw != 1 ||
      section.scoring.loss != 0 ||
      section.scoring.bye != 2) {
    throw const TournamentException(
      'This preset needs single games and standard 1 / ½ / 0 scoring. Use a custom schedule for other settings.',
    );
  }
  final players =
      section.players.map(event.player).where((p) => !p.withdrawn).toList()
        ..sort((a, b) {
          for (final comparison in [
            b.rating.compareTo(a.rating),
            a.name.compareTo(b.name),
            a.id.compareTo(b.id),
          ]) {
            if (comparison != 0) return comparison;
          }
          return 0;
        });
  if (players.length < 4) {
    throw const TournamentException(
      'Acceleration needs at least four active players.',
    );
  }
  return {
    for (final p in players.take(players.length ~/ 2))
      p.id: List.filled(rounds, 2),
  };
}
