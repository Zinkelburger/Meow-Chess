part of 'tournament_controller_core.dart';

/// Bughouse partnerships (`Section.partners`): formed before round 1 and
/// fixed once the section is paired.
mixin _BughouseCommands on _CommandContext {
  /// Replaces the partnerships of [sectionId] with [partners], each a pair
  /// of the section's players; a player appears in at most one pair.
  /// Players left out are unpartnered and sit out with a zero-point bye.
  void setPartners(String sectionId, List<List<String>> partners) {
    final e = event!, s = _section(sectionId);
    if (s.format != Format.bughouse) {
      throw TournamentException('${s.name} is not a bughouse section.');
    }
    if (s.rounds.isNotEmpty) {
      throw const TournamentException(
        'Partnerships are fixed once round 1 is posted.',
      );
    }
    final seen = <String>{};
    for (final pair in partners) {
      if (pair.length != 2 || pair[0] == pair[1]) {
        throw const TournamentException(
          'A partnership is two different players.',
        );
      }
      for (final id in pair) {
        final p = e.player(id);
        if (!s.players.contains(id)) {
          throw TournamentException('${p.name} is not in ${s.name}.');
        }
        if (!seen.add(id)) {
          throw TournamentException('${p.name} is in two partnerships.');
        }
      }
    }
    String key(List<String> pair) => ([...pair]..sort()).join('|');
    final before = {for (final p in s.partners) key(p): p};
    final after = {for (final p in partners) key(p): p};
    final added = [
      for (final k in after.keys)
        if (!before.containsKey(k)) after[k]!,
    ];
    final removed = [
      for (final k in before.keys)
        if (!after.containsKey(k)) before[k]!,
    ];
    String names(List<String> pair) =>
        pair.map((id) => e.player(id).name).join(' and ');
    final label = added.length == 1 && removed.isEmpty
        ? 'Pair ${names(added.single)}'
        : removed.length == 1 && added.isEmpty
        ? 'Unpair ${names(removed.single)}'
        : 'Set partnerships in ${s.name}';
    change(
      label,
      e.copy(
        sections: [
          for (final x in e.sections)
            x.id == s.id ? x.copy(partners: partners, unrated: true) : x,
        ],
      ),
    );
  }
}
