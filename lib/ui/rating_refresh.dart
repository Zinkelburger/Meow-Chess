import '../application/member_lookup.dart';
import 'package:flutter/foundation.dart';

import '../domain/model.dart';
import '../domain/rating_update.dart';
import '../domain/member_observation.dart';
import '../domain/name_match.dart';
import '../application/member_lookup_batch.dart';
import '../application/failures.dart';
import '../application/diagnostics.dart';
import '../application/tournament_controller.dart';

/// A review draft, independent of the right-hand player editor. Fetching never
/// changes pairing ratings. Relevant player edits invalidate only that row.
class RatingRefresh extends ChangeNotifier {
  RatingRefresh(this.controller, {required this.lookup});
  final TournamentController controller;
  final MemberLookup lookup;
  final observations = <String, MemberObservation>{};
  final failures = <String, String>{};
  final selected = <String>{};
  Event? snapshot;
  String category = 'R';
  bool active = false, busy = false;
  String? notice;
  int _generation = 0;

  /// Lookups awaiting one batched save, so a refresh adds one revision.
  final _unrecorded = <String, Json>{};
  String? _unrecordedEvent;

  void _recordMemberships() {
    if (_unrecordedEvent case final eventId? when _unrecorded.isNotEmpty) {
      controller.recordMemberships(eventId, {..._unrecorded});
    }
    _unrecorded.clear();
  }

  void _saveFailed(Object error, StackTrace stack) {
    notice =
        'Could not save membership checks. ${plainMessage(error)} '
        'Completed lookups are retained; retry refresh to save them.';
    Diagnostics.record(
      'save rating refresh memberships',
      'failed',
      error: error,
      stack: stack,
    );
  }

  Player? original(String id) =>
      snapshot?.players.where((p) => p.id == id).firstOrNull;

  int? proposed(Player p) => observations[p.id]?.ratings[category];

  String? problem(Player p) {
    final old = original(p.id);
    if (old == null) {
      return 'Added after this refresh. Refresh again to include.';
    }
    if (controller.event?.id != snapshot?.id) {
      return 'Event changed. Refresh again.';
    }
    if (old.memberId != p.memberId) {
      return 'USCF ID changed. Refresh again to check it.';
    }
    if (old.rating != p.rating) return 'Your edit is kept.';
    if (p.memberId.trim().isEmpty) {
      return 'No USCF ID. Click the player to add one, or keep this rating.';
    }
    if (failures[p.id] case final message?) return message;
    final m = observations[p.id];
    if (m == null) {
      return busy ? 'Waiting for USCF…' : 'Not checked. Retry refresh.';
    }
    return ratingUpdateProblem(
      current: controller.event!,
      snapshot: snapshot!,
      player: p,
      observation: m,
      category: category,
    );
  }

  bool canApply(Player p) => problem(p) == null;

  /// The US Chess name looks like somebody else, which usually means a
  /// mistyped ID. Such rows start unticked.
  bool nameMismatch(Player p) {
    final m = observations[p.id];
    return m != null &&
        m.id == p.memberId &&
        !namesLookAlike(p.name, m.name, lastName: lastNameOf(m.reportName));
  }

  /// In the review but without an ID to look up.
  bool missingId(Player p) =>
      original(p.id) != null && p.memberId.trim().isEmpty;

  /// US Chess answered for this ID but has no rating in the chosen system.
  bool unratedAtUscf(Player p) {
    final m = observations[p.id];
    final rating = proposed(p);
    return m != null &&
        m.id == p.memberId &&
        original(p.id)?.rating == p.rating &&
        (rating == null || rating <= 0);
  }

  /// The chosen rating is already the player's verified rating.
  bool upToDate(Player p) =>
      observations[p.id]?.alreadyApplied(p, category) ?? false;

  /// Ticked by default: applicable and plainly the same person.
  bool suggested(Player p) => canApply(p) && !nameMismatch(p);

  /// The supplement most lookups came from, for the column heading.
  String? get supplementDate {
    final counts = <String, int>{};
    for (final m in observations.values) {
      if (m.supplementDate case final date?) {
        counts[date] = (counts[date] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }

  int get checkedCount => observations.length + failures.length;
  bool largeChange(Player p) =>
      (proposed(p) ?? 0) > 0 &&
      (p.rating == 0 || (proposed(p)! - p.rating).abs() > 50);
  List<Player> get approved => controller.event!.players
      .where((p) => selected.contains(p.id) && canApply(p))
      .toList();
  int get foundCount => controller.event!.players
      .where(
        (p) => original(p.id)?.memberId == p.memberId && (proposed(p) ?? 0) > 0,
      )
      .length;

  void select(Player p, bool value) {
    if (busy || !canApply(p)) return;
    value ? selected.add(p.id) : selected.remove(p.id);
    notifyListeners();
  }

  void selectAll(bool value) {
    if (busy) return;
    selected.clear();
    if (value) {
      selected.addAll(
        controller.event!.players.where(canApply).map((p) => p.id),
      );
    }
    notifyListeners();
  }

  Future<void> fetch({String? ratingCategory}) async {
    try {
      _recordMemberships();
    } catch (error, stack) {
      _saveFailed(error, stack);
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    final event = controller.event!;
    _unrecordedEvent = event.id;
    if (ratingCategory != null) category = ratingCategory;
    snapshot = event;
    active = busy = true;
    notice = null;
    observations.clear();
    failures.clear();
    selected.clear();
    Diagnostics.record(
      'refresh USCF ratings',
      'started',
      context: {'players': event.players.length, 'category': category},
    );
    notifyListeners();
    bool current() => generation == _generation;
    try {
      final outcome = await const MemberLookupBatch().run(
        event.players,
        lookup: (id) => lookup(id),
        isCurrent: () => current() && controller.event?.id == event.id,
        onFound: (player, found) {
          _unrecorded[player.id] = found.toJson();
          observations[player.id] = found;
          final live = controller.event!.players
              .where((x) => x.id == player.id)
              .firstOrNull;
          if (live != null && suggested(live)) selected.add(live.id);
          notifyListeners();
        },
        onFailure: (player, error, stack) {
          Diagnostics.record(
            'lookup USCF rating',
            'failed',
            context: {'playerId': player.id},
            error: error,
            stack: stack,
          );
          failures[player.id] =
              '${plainMessage(error)} Retry later or edit the player manually.';
          notifyListeners();
        },
      );
      if (!current()) return;
      if (outcome == MemberBatchOutcome.providerStopped) {
        notice =
            'USCF stopped responding. Review completed lookups, retry later, or keep current ratings.';
      } else if (outcome == MemberBatchOutcome.cancelled) {
        notice = 'Event changed. Refresh again for the current roster.';
      }
      try {
        _recordMemberships();
      } catch (error, stack) {
        _saveFailed(error, stack);
        return;
      }
      Diagnostics.record(
        'refresh USCF ratings',
        'completed',
        context: {
          'found': foundCount,
          'failures': failures.length,
          'missingIds': event.players.where((p) => p.memberId.isEmpty).length,
        },
      );
      if (event.players.every((p) => p.memberId.trim().isEmpty)) {
        notice =
            'No USCF IDs to look up. Nothing changed. Add IDs in player details if you want ratings later.';
      }
    } catch (error, stack) {
      if (current()) {
        notice =
            'Lookup stopped. ${plainMessage(error)} '
            'Review completed lookups, retry later, or keep current ratings.';
        Diagnostics.record(
          'refresh USCF ratings',
          'failed',
          error: error,
          stack: stack,
        );
      }
    } finally {
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void stop() {
    _generation++;
    busy = false;
    notice =
        'Stopped. You can review completed lookups or keep current ratings.';
    try {
      _recordMemberships();
    } catch (error, stack) {
      _saveFailed(error, stack);
    } finally {
      notifyListeners();
    }
  }

  int apply() {
    if (busy || !active || controller.event?.id != snapshot?.id) {
      throw const TournamentException(
        'Refresh again before confirming ratings.',
      );
    }
    final ids = approved.map((p) => p.id).toSet();
    if (ids.isEmpty) return 0;
    _recordMemberships();
    controller.applyReviewedRatings(
      snapshot: snapshot!,
      observations: observations,
      playerIds: ids,
      category: category,
    );
    discard();
    return ids.length;
  }

  /// Supplements carry every category, so switching only re-reads them.
  void showCategory(String value) {
    if (busy || value == category) return;
    category = value;
    selected
      ..clear()
      ..addAll(controller.event!.players.where(suggested).map((p) => p.id));
    notifyListeners();
  }

  /// Closes the review. Completed membership checks are saved first, even
  /// mid-lookup; if that save fails the review stays open with the notice.
  void discard() {
    _generation++;
    try {
      _recordMemberships();
    } catch (error, stack) {
      busy = false;
      _saveFailed(error, stack);
      notifyListeners();
      return;
    }
    active = busy = false;
    snapshot = null;
    _unrecorded.clear();
    _unrecordedEvent = null;
    observations.clear();
    failures.clear();
    selected.clear();
    notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
