import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import '../support.dart';

void main() {
  test('lots reorder a quad reproducibly and are audited with the seed', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final section = c.event!.sections.single;
    final before = section.players;
    c.drawLots(section.id, seed: 7);
    final after = c.event!.sections.single.players;
    expect(after.toSet(), before.toSet());
    expect(after, isNot(before));
    expect(
      c.repository.history().first['action'],
      'Draw lots for ${section.name} (seed 7)',
    );
    // The same seed draws the same numbers again.
    c.undo();
    expect(c.event!.sections.single.players, before);
    c.drawLots(section.id, seed: 7);
    expect(c.event!.sections.single.players, after);
  });

  test('lots are refused for a Swiss and once a round is posted', () async {
    final swiss = fixture(count: 4, format: Format.swiss);
    addTearDown(swiss.dispose);
    expect(
      () => swiss.drawLots(swiss.event!.sections.single.id, seed: 1),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('round robins and quads'),
        ),
      ),
    );
    final quad = fixture(count: 4);
    addTearDown(quad.dispose);
    quad.post(await quad.propose());
    expect(
      () => quad.drawLots(quad.event!.sections.single.id, seed: 1),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('fixed once a round is posted'),
        ),
      ),
    );
  });
}
