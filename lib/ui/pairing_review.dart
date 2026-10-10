import '../application/tournament_controller.dart' show PairingBatch;
import '../domain/model.dart';

/// The pairing decisions a director checks as soon as a round is posted
/// (rule 29E TIP: the director reviews what the pairer did). Routine
/// transpositions stay in the round's explanations, for History and MCP.
///
/// The Swiss engine reports its decisions as prose only
/// (`SwissProposal.explanations` and `Round.explanations` are
/// `List<String>`), so each kind is recognised by a fragment of the
/// engine's wording. The fragments live here and nowhere else;
/// test/ui/pairing_review_test.dart fails if the engine's wording drifts.
enum PairingReview {
  /// 27A1: no pairing without repeat games exists, so a repeat is allowed.
  repeatMeeting('meeting is allowed'),

  /// 28L3: every player has had a bye or forfeit win, so one gets another.
  repeatBye('28L3 could not'),

  /// 29E5f: a player receives the same color for the third time in a row.
  thirdColor('third time'),

  /// 29D2, 29E5: score groups could not be paired in order; a search found
  /// the closest legal pairing instead.
  searchFallback('closest legal pairing');

  const PairingReview(this.marker);

  /// The fragment of the engine's explanation that identifies this kind.
  final String marker;

  /// The kind [explanation] reports, or null for a routine one.
  static PairingReview? of(String explanation) =>
      values.where((kind) => explanation.contains(kind.marker)).firstOrNull;
}

/// What to show after posting [batch]: each section's pairing problem,
/// then each posted round's explanations worth checking, prefixed with the
/// section name. Sections no longer in [event] are left out.
List<String> postReviewNotes(Event event, PairingBatch batch) {
  Section? sectionOf(String id) =>
      event.sections.where((s) => s.id == id).firstOrNull;
  return [
    for (final MapEntry(key: id, value: note) in batch.issues.entries)
      if (sectionOf(id) case final s?) '${s.name}: $note',
    for (final MapEntry(key: id, value: round) in batch.rounds.entries)
      if (sectionOf(id) case final s?)
        for (final line in round.explanations)
          if (PairingReview.of(line) != null) '${s.name}: $line',
  ];
}
