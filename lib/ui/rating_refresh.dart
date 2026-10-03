import 'package:flutter/foundation.dart';

import '../domain/model.dart';
import '../infrastructure/ratings_api.dart';
import '../application/failures.dart';
import '../application/diagnostics.dart';
import '../application/tournament_controller.dart';

typedef RatingLookup =
    Future<MemberObservation?> Function(
      TournamentController controller,
      String memberId,
    );

/// A review draft, independent of the right-hand player editor. Fetching never
/// changes pairing ratings. Relevant player edits invalidate only that row.
class RatingRefresh extends ChangeNotifier {
  RatingRefresh(this.controller, {required this.lookup});
  final TournamentController controller;
  final RatingLookup lookup;
  final observations = <String, MemberObservation>{};
  final failures = <String, String>{};
  final selected = <String>{};
  Event? snapshot;
  String category = 'R';
  bool active = false, busy = false;
  String? notice;
  int _generation = 0;

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
    if (old.memberId != p.memberId || old.rating != p.rating) {
      return 'Edited since lookup. Refresh again to review this player.';
    }
    if (p.memberId.trim().isEmpty) {
      return 'No USCF ID. Double-click to add one, or keep this rating.';
    }
    if (failures[p.id] case final message?) return message;
    final m = observations[p.id];
    if (m == null) {
      return busy ? 'Waiting for USCF…' : 'Not checked. Retry refresh.';
    }
    if ((proposed(p) ?? 0) <= 0) {
      return 'Unrated / no published ${const {'R': 'Regular', 'Q': 'Quick', 'B': 'Blitz'}[category]} rating. Current rating kept.';
    }
    if (m.supplementDate == null) return 'No dated supplement. Retry later.';
    if (controller.event!.sectionOf(p.id)?.rounds.isNotEmpty ?? false) {
      return 'Pairings posted. Pairing rating kept.';
    }
    if (m.alreadyApplied(p, category)) return 'Already up to date.';
    return null;
  }

  bool canApply(Player p) => problem(p) == null;
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
    final generation = ++_generation;
    final event = controller.event!;
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
    // Deduplicate IDs, but retain a review result on every player row.
    final byId = <String, MemberObservation?>{};
    for (final p in event.players) {
      if (!current()) return;
      if (controller.event?.id != event.id) {
        stop();
        return;
      }
      if (p.memberId.trim().isEmpty) continue;
      try {
        final found = byId.containsKey(p.memberId)
            ? byId[p.memberId]
            : await lookup(controller, p.memberId);
        if (!current()) return;
        if (found == null || found.id != p.memberId) {
          throw const TournamentException(
            'No matching USCF member. Check the ID in player details, or keep the current rating.',
          );
        }
        byId[p.memberId] = found;
        observations[p.id] = found;
        final live = controller.event!.players
            .where((x) => x.id == p.id)
            .firstOrNull;
        if (live != null && canApply(live)) selected.add(p.id);
      } catch (e, stack) {
        Diagnostics.record(
          'lookup USCF rating',
          'failed',
          context: {'playerId': p.id},
          error: e,
          stack: stack,
        );
        if (!current()) return;
        final message = plainMessage(e);
        failures[p.id] = '$message Retry later or edit the player manually.';
        if (message.contains('429') ||
            message.contains('rate limit') ||
            message.contains('API key') ||
            message.contains('Public US Chess access')) {
          notice =
              'USCF stopped responding. Review completed lookups, retry later, or keep current ratings.';
          break;
        }
      }
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!current()) return;
    busy = false;
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
    notifyListeners();
  }

  void stop() {
    _generation++;
    busy = false;
    notice =
        'Stopped. You can review completed lookups or keep current ratings.';
    notifyListeners();
  }

  int apply() {
    if (busy || !active || controller.event?.id != snapshot?.id) {
      throw const TournamentException(
        'Refresh again before confirming ratings.',
      );
    }
    final ids = approved.map((p) => p.id).toSet();
    if (ids.isEmpty) return 0;
    controller.change(
      'Apply ${ids.length} monthly supplement ratings',
      controller.event!.copy(
        players: [
          for (final p in controller.event!.players)
            if (ids.contains(p.id))
              p.copy(
                rating: proposed(p),
                ratingEvidence: {
                  ...p.ratingEvidence,
                  ...observations[p.id]!.toJson(),
                  'kind': 'monthly supplement',
                  'category': category,
                },
                membershipEvidence:
                    (DateTime.tryParse(
                          '${p.membershipEvidence['retrievedAt']}',
                        )?.isAfter(
                          DateTime.tryParse(observations[p.id]!.retrievedAt) ??
                              DateTime(1970),
                        ) ??
                        false)
                    ? p.membershipEvidence
                    : observations[p.id]!.toJson(),
              )
            else
              p,
        ],
      ),
    );
    discard();
    return ids.length;
  }

  void discard() {
    _generation++;
    active = busy = false;
    snapshot = null;
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
