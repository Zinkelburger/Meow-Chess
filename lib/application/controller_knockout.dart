part of 'tournament_controller_core.dart';

/// Knockout brackets: the director's decision on a drawn match when the
/// section plays no tie-break games.
mixin _KnockoutCommands on _CommandContext {
  /// Records that [playerId] advances from the drawn match on [board] of
  /// [sectionId], with the director's [reason] (blank is recorded as the
  /// director's decision). One audited revision, undone like any other.
  void advanceKnockout(
    String sectionId,
    int board,
    String playerId, {
    String reason = '',
  }) {
    final e = event!, section = _section(sectionId);
    if (section.format != Format.knockout) {
      throw const TournamentException('That section is not a knockout.');
    }
    final decided = knockoutDecided(e, section, board, playerId, reason);
    final match = knockoutBracket(e, decided).stages
        .expand((s) => s.matches)
        .firstWhere((m) => m.board == board && m.advanced == playerId);
    change(
      '${e.player(playerId).name} advances over ${e.player(match.eliminated!).name}',
      e.copy(
        sections: [for (final s in e.sections) s.id == sectionId ? decided : s],
      ),
    );
  }
}
