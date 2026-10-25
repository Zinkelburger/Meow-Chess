import 'model.dart';

/// Registration lists name each entry's section in words ("Under 1000",
/// "U1000", "championship"). Two labels name the same section when they
/// agree ignoring case, spacing, punctuation and "Under" written as "U".
String sectionKey(String label) => label
    .toLowerCase()
    .replaceAll(RegExp(r'\bunder\s*(?=\d)'), 'u')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Where the section labels of a registration list put its entries: into
/// an existing section that has not been paired, into a new Swiss section
/// named by the label, or nowhere, with the reason. Players already in a
/// section stay where they are.
class SectionPlan {
  SectionPlan._(this.joins, this.creates, this.skipped);

  /// Player ID → the existing section they join.
  final Map<String, String> joins;

  /// A new section's name, as the list first writes it → its players.
  final Map<String, List<String>> creates;

  /// Player ID → why they stay out of every section.
  final Map<String, String> skipped;

  bool get isEmpty => joins.isEmpty && creates.isEmpty;

  /// The new section [playerId] would start, or null.
  String? createdFor(String playerId) =>
      creates.entries.where((c) => c.value.contains(playerId)).firstOrNull?.key;
}

/// Plans where [labels] (player ID → section label) put each player of
/// [event], or each new player about to be added to it.
SectionPlan planSections(Event event, Map<String, String> labels) {
  final joins = <String, String>{}, skipped = <String, String>{};
  final creates = <String, List<String>>{};
  final names = <String, String>{};
  for (final MapEntry(key: id, value: label) in labels.entries) {
    final key = sectionKey(label);
    if (key.isEmpty) continue;
    if (event.players.any((p) => p.id == id) && event.sectionOf(id) != null) {
      continue;
    }
    final matches = [
      for (final s in event.sections)
        if (sectionKey(s.name) == key) s,
    ];
    if (matches.length > 1) {
      skipped[id] =
          '${matches.length} sections match "${label.trim()}". Choose one on the Players page.';
    } else if (matches.singleOrNull case final s?) {
      if (s.rounds.isNotEmpty) {
        skipped[id] =
            '${s.name} is already paired. Add late entries from the player card.';
      } else {
        joins[id] = s.id;
      }
    } else {
      final name = names.putIfAbsent(key, () => label.trim());
      (creates[name] ??= []).add(id);
    }
  }
  return SectionPlan._(joins, creates, skipped);
}

/// [event] with [plan] carried out. Every planned player must already be in
/// the event. New sections are Swiss with [rounds] planned rounds, on the
/// next free boards; with [rounds] 0 none is created and their players stay
/// out of every section. A section that grows keeps its boards unless it
/// now runs into another's.
Event applySectionPlan(
  Event event,
  SectionPlan plan, {
  required int rounds,
  required String Function() newId,
}) {
  if (plan.isEmpty) return event;
  if (plan.creates.isNotEmpty && rounds != 0 && (rounds < 1 || rounds > 32)) {
    throw const TournamentException(
      'Enter the number of rounds for the new sections, from 1 to 32.',
    );
  }
  final joining = <String, List<String>>{};
  for (final MapEntry(key: player, value: section) in plan.joins.entries) {
    (joining[section] ??= []).add(player);
  }
  // Players join in the order the event lists them, as an import adds them.
  final order = {for (final (i, p) in event.players.indexed) p.id: i};
  int byOrder(String a, String b) => order[a]!.compareTo(order[b]!);
  final grown = [
    for (final s in event.sections)
      if (joining[s.id] case final ids?)
        s.copy(
          players: [
            ...s.players,
            ...[...ids]..sort(byOrder),
          ],
          // A manual quad schedule names roster slots, which shift.
          quadPairings: const [],
        )
      else
        s,
  ];
  final sections = keepBoardRanges(event.sections, grown, joining.keys.toSet());
  for (final MapEntry(key: name, value: ids)
      in rounds == 0
          ? const <MapEntry<String, List<String>>>[]
          : plan.creates.entries) {
    sections.add(
      Section(
        id: newId(),
        name: name,
        players: [...ids]..sort(byOrder),
        plannedRounds: rounds,
        boardStart: nextBoard(sections),
      ),
    );
  }
  return event.copy(sections: sections);
}
