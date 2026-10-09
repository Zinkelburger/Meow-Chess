import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/web_roster.dart';
import '../support.dart';

void main() {
  test('the 00000000 placeholder never matches a web roster entry by ID', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.savePlayer(c.event!.player('p0').copy(memberId: '00000000'));
    final incoming = Player(
      id: 'web-1',
      name: 'Somebody Else',
      memberId: '00000000',
      rating: 1200,
    );
    final review = RosterReview(
      c.event!,
      'https://example.org/entries',
      [ImportRow(2, 'Somebody Else', incoming, null)],
    );
    final change = review.changes.single;
    expect(change.existing, isNull);
    expect(change.problem, isNull);
  });
}
