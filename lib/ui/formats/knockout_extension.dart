import '../../domain/knockout.dart';
import '../../domain/model.dart';
import '../dialogs.dart' show FieldSpec;
import '../format_extensions.dart';

/// What a knockout adds to the section panel: games per match and what
/// decides a drawn match. Both are announced rules; games per match is
/// fixed once round 1 is posted, the tie-break may still change.
final knockoutFormatExtension = FormatExtension(
  format: Format.knockout,
  fields: (current, {required locked}) => [
    FieldSpec(
      'gamesPerMatch',
      'Games per match',
      enabled: !locked,
      options: const {'1': '1 game', '2': '2 games, one of each color'},
    ),
    FieldSpec('tiebreak', 'Drawn match', options: knockoutTiebreakLabels),
  ],
  values: (section) => {
    'gamesPerMatch': '${knockoutGamesPerMatch(section)}',
    'tiebreak': knockoutTiebreak(section),
  },
  apply: (section, values) {
    final games =
        int.tryParse(values['gamesPerMatch'] ?? '') ??
        knockoutGamesPerMatch(section);
    final bracket = {
      ...section.bracket,
      'gamesPerMatch': games,
      'tiebreak': values['tiebreak'] ?? knockoutTiebreak(section),
    };
    if (knockoutSettingsProblem(bracket) case final problem?) {
      throw TournamentException(problem);
    }
    return section.copy(
      bracket: bracket,
      doubleGames: games == 2,
      // The bracket's rounds follow the field; tie-break postings are added
      // as they are played.
      plannedRounds: section.rounds.isEmpty && section.players.length >= 2
          ? knockoutStages(section.players.length)
          : null,
    );
  },
  summary: knockoutSummary,
  problem: knockoutProblem,
);
