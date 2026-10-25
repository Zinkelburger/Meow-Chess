import 'dart:math';
import 'model.dart';
import 'pairing.dart';
import 'swiss.dart';

class SimulationConfig {
  const SimulationConfig({
    this.players = 32,
    this.rounds = 5,
    this.seed = 1,
    this.drawPercent = 25,
    this.forfeitPercent = 2,
    this.withdrawPercent = 0,
  });
  final int players, rounds, seed, drawPercent, forfeitPercent, withdrawPercent;
  void validate() {
    if (players < 4 ||
        players > 256 ||
        rounds < 1 ||
        rounds > 12 ||
        seed < 0 ||
        seed > 2147483647 ||
        [
          drawPercent,
          forfeitPercent,
          withdrawPercent,
        ].any((p) => p < 0 || p > 100) ||
        drawPercent + forfeitPercent > 100) {
      throw const TournamentException(
        'Use 4–256 players, 1–12 rounds, a seed from 0–2147483647 and percentages from 0–100. Draw + forfeit percentages cannot exceed 100.',
      );
    }
  }
}

class SimulationResult {
  const SimulationResult(this.event, this.stopReason);
  final Event event;
  final String? stopReason;
}

SimulationResult simulateTournament(SimulationConfig config) {
  config.validate();
  final random = Random(config.seed);
  var nextId = 0;
  var event = Event(
    id: 'simulation-${config.seed}',
    name: 'Swiss practice — seed ${config.seed}',
    date: '2024-01-01',
    practice: true,
    notes:
        'Synthetic simulation; $swissPolicy; seed ${config.seed}; '
        '${config.players} players; ${config.rounds} rounds; '
        'draw ${config.drawPercent}%; forfeit ${config.forfeitPercent}%; withdrawal ${config.withdrawPercent}% per active player per round.',
    players: [
      for (var i = 0; i < config.players; i++)
        Player(
          id: 'p$i',
          name: 'Practice Player ${i + 1}',
          rating: 600 + random.nextInt(1801),
          checkedIn: true,
          source: 'Synthetic simulation seed ${config.seed}',
        ),
    ],
    sections: [
      Section(
        id: 's',
        name: 'Practice Swiss',
        plannedRounds: config.rounds,
        players: [for (var i = 0; i < config.players; i++) 'p$i'],
      ),
    ],
  );
  String? stopped;
  for (var n = 1; n <= config.rounds; n++) {
    if (n > 1) {
      event = event.copy(
        players: [
          for (final p in event.players)
            p.withdrawn
                ? p
                : p.copy(
                    withdrawn: random.nextInt(100) < config.withdrawPercent,
                  ),
        ],
      );
    }
    try {
      final section = event.sections.single;
      final round = proposeRound(event, section, () => 'g${nextId++}');
      final decided = round.copy(
        games: [
          for (final g in round.games)
            g.copy(outcome: _outcome(event, g, config, random)),
        ],
      );
      event = event.copy(
        sections: [
          section.copy(rounds: [...section.rounds, decided]),
        ],
      );
      validateEvent(event);
    } on TournamentException catch (error) {
      stopped = 'Stopped before round $n: ${error.message}';
      break;
    }
  }
  return SimulationResult(
    event.copy(
      notes: '${event.notes}\n${stopped ?? 'Completed all requested rounds.'}',
    ),
    stopped,
  );
}

Outcome _outcome(
  Event event,
  Game game,
  SimulationConfig config,
  Random random,
) {
  final roll = random.nextInt(100);
  if (roll < config.forfeitPercent) {
    return random.nextBool() ? Outcome.whiteForfeit : Outcome.blackForfeit;
  }
  if (roll < config.forfeitPercent + config.drawPercent) return Outcome.draw;
  final expected =
      1 /
      (1 +
          pow(
            10,
            (event.player(game.black).rating -
                    event.player(game.white).rating) /
                400,
          ));
  return random.nextDouble() < expected ? Outcome.whiteWin : Outcome.blackWin;
}
