import '../domain/member_observation.dart';
import '../domain/model.dart';
import 'member_lookup.dart';

enum MemberBatchOutcome { completed, cancelled, providerStopped }

/// Serial, rate-limited reads of provider evidence. This service never writes
/// tournament data: each caller decides when to commit and what needs approval.
class MemberLookupBatch {
  const MemberLookupBatch({
    this.interval = const Duration(milliseconds: 500),
    this.wait = Future<void>.delayed,
  });

  final Duration interval;
  final Future<void> Function(Duration) wait;

  Future<MemberBatchOutcome> run(
    Iterable<Player> players, {
    required MemberLookup lookup,
    required bool Function() isCurrent,
    required void Function(Player, MemberObservation) onFound,
    required void Function(Player, Object, StackTrace) onFailure,
    void Function(Player)? onMissingId,
  }) async {
    final results = <String, MemberObservation>{};
    final failures = <String, (Object, StackTrace)>{};
    var requested = false;
    for (final player in players) {
      if (!isCurrent()) return MemberBatchOutcome.cancelled;
      final id = player.memberId;
      if (id.trim().isEmpty) {
        onMissingId?.call(player);
        continue;
      }
      if (!results.containsKey(id) && !failures.containsKey(id)) {
        if (requested) {
          await wait(interval);
          if (!isCurrent()) return MemberBatchOutcome.cancelled;
        }
        requested = true;
        try {
          final found = await lookup(id);
          if (!isCurrent()) return MemberBatchOutcome.cancelled;
          if (found == null || found.id != id) {
            throw const TournamentException(
              'No matching USCF member. Check the ID or keep the local record.',
            );
          }
          results[id] = found;
        } catch (error, stack) {
          if (!isCurrent()) return MemberBatchOutcome.cancelled;
          failures[id] = (error, stack);
        }
      }
      if (failures[id] case final failure?) {
        onFailure(player, failure.$1, failure.$2);
        if (failure.$1 case MemberLookupFailure(stopsBatch: true)) {
          return MemberBatchOutcome.providerStopped;
        }
      } else {
        // Deliberately outside the lookup catch: persistence/UI errors must not
        // be mislabeled as provider failures or allow the batch to keep writing.
        onFound(player, results[id]!);
      }
    }
    return isCurrent()
        ? MemberBatchOutcome.completed
        : MemberBatchOutcome.cancelled;
  }
}
