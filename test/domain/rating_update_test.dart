import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/member_observation.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/rating_update.dart';

MemberObservation seen({
  String id = '12345678',
  int? rating = 1650,
  String retrievedAt = '2026-10-05T12:00:00Z',
  String? supplementDate = '2026-10-01',
}) => MemberObservation(
  id: id,
  name: 'Player',
  retrievedAt: retrievedAt,
  supplementDate: supplementDate,
  ratings: {'R': rating},
);

void main() {
  final player = Player(
    id: 'p',
    name: 'Player',
    memberId: '12345678',
    rating: 1500,
  );
  final event = Event(
    id: 'e',
    name: 'Club',
    date: '2026-10-09',
    timeControl: 'G/90 d5',
    players: [player],
    sections: [
      Section(id: 's', name: 'Open', players: ['p']),
    ],
  );

  String? problem(MemberObservation o, {Event? current, Player? p}) =>
      ratingUpdateProblem(
        current: current ?? event,
        snapshot: event,
        player: p ?? player,
        observation: o,
        category: 'R',
      );

  test('accepts a dated, matching, in-range supplement rating', () {
    expect(problem(seen()), isNull);
  });

  test('rejects mismatched, missing, out-of-range and undated evidence', () {
    expect(problem(seen(id: '87654321')), contains('does not match'));
    expect(problem(seen(rating: null)), contains('No Regular rating'));
    expect(problem(seen(rating: 0)), contains('No Regular rating'));
    expect(problem(seen(rating: 4001)), contains('No Regular rating'));
    expect(problem(seen(supplementDate: null)), contains('No dated'));
    expect(
      problem(seen(), p: player.copy(rating: 1501)),
      contains('Edited since lookup'),
    );
  });

  test('applied evidence is reported as already up to date', () {
    final applied = applyRatingObservation(player, seen(), 'R');
    expect(applied.rating, 1650);
    expect(applied.ratingEvidence['category'], 'R');
    final current = event.copy(players: [applied]);
    expect(
      ratingUpdateProblem(
        current: current,
        snapshot: current,
        player: applied,
        observation: seen(),
        category: 'R',
      ),
      'Already up to date.',
    );
  });

  test('a newer membership check is not replaced by older evidence', () {
    final newer = player.copy(
      membershipEvidence: {'retrievedAt': '2026-10-07T00:00:00Z'},
    );
    expect(
      applyRatingObservation(newer, seen(), 'R').membershipEvidence,
      newer.membershipEvidence,
    );
    final older = player.copy(
      membershipEvidence: {'retrievedAt': '2026-10-01T00:00:00Z'},
    );
    expect(
      applyRatingObservation(
        older,
        seen(),
        'R',
      ).membershipEvidence['retrievedAt'],
      '2026-10-05T12:00:00Z',
    );
  });
}
