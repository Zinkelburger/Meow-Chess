import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/eligibility.dart';
import 'package:meow_chess/domain/model.dart';

Player rated(int rating, {String id = 'p', bool house = false}) =>
    Player(id: id, name: 'Player', rating: rating, house: house);

Event tuesday({
  int playUp = 200,
  List<Player> players = const [],
  Map<String, String> allowed = const {},
}) => Event(
  id: 'e',
  name: 'Tuesday Night Swiss',
  date: '2026-11-17',
  playUpLimit: playUp,
  players: players,
  sections: [
    Section(
      id: 'open',
      name: 'Open',
      players: [for (final p in players) p.id],
      rangeExceptions: allowed,
    ),
    Section(id: 'u1910', name: 'U1910', players: const [], ratingCeiling: 1910),
    Section(id: 'u1510', name: 'U1510', players: const [], ratingCeiling: 1510),
    Section(id: 'side', name: 'Side Games', players: const [], sideGames: true),
  ],
);

void main() {
  test('a name announces its rating cap', () {
    expect(ratingCapInName('U1800'), 1800);
    expect(ratingCapInName('Under 1800'), 1800);
    expect(ratingCapInName(' u-1000 '), 1000);
    expect(ratingCapInName('U1800 Reserve'), 1800);
    expect(ratingCapInName('Open'), 0);
    expect(ratingCapInName('Under Twelve'), 0);
    expect(ratingCapInName('Quad 1'), 0);
  });

  test('a section states its rating rule for the roster', () {
    final e = tuesday();
    Section s(String id) => e.sections.firstWhere((x) => x.id == id);
    expect(
      eligibilityRule(e, s('open')),
      'Playing up into Open takes 1710 or more. Unrated players may enter.',
    );
    expect(
      eligibilityRule(e, s('u1910')),
      'U1910 is for players rated under 1910. Playing up into U1910 takes '
      '1310 or more. Unrated players may enter.',
    );
    expect(
      eligibilityRule(e, s('u1510')),
      'U1510 is for players rated under 1510.',
    );
    expect(eligibilityRule(tuesday(playUp: 0), s('open')), '');
  });

  test('the section below is the next cap down', () {
    final e = tuesday();
    Section s(String id) => e.sections.firstWhere((x) => x.id == id);
    expect(sectionBelow(e, s('open'))!.id, 'u1910');
    expect(sectionBelow(e, s('u1910'))!.id, 'u1510');
    expect(sectionBelow(e, s('u1510')), isNull);
    expect(playUpFloor(e, s('open')), 1710);
    expect(playUpFloor(e, s('u1910')), 1310);
    expect(playUpFloor(e, s('u1510')), 0);
    expect(playUpFloor(e, s('side')), 0);
    expect(playUpFloor(tuesday(playUp: 0), s('open')), 0);
  });

  test('playing up takes a rating within the limit of the cap below', () {
    final e = tuesday();
    final open = e.sections.first;
    expect(playUpProblem(e, rated(1710), open), isNull);
    expect(playUpProblem(e, rated(2100), open), isNull);
    expect(
      playUpProblem(e, rated(1500), open),
      'Rated 1500: playing up into Open takes 1710 or more, within 200 '
      'points of the U1910 cap.',
    );
    // Club policy: unrated players may play in any section.
    expect(playUpProblem(e, rated(0), open), isNull);
    expect(playUpProblem(e, rated(1500, house: true), open), isNull);
    expect(
      playUpProblem(
        tuesday(allowed: {'p': 'Won the section last month'}),
        rated(1500),
        tuesday(allowed: {'p': 'Won the section last month'}).sections.first,
      ),
      isNull,
    );
    expect(eligibilityProblem(e, rated(1500), open), startsWith('Rated 1500'));
    // A cap still counts: 1950 is too strong for U1910.
    expect(
      eligibilityProblem(e, rated(1950), e.sections[1]),
      contains('U1910 is for players rated under 1910'),
    );
  });

  test('the section a rating belongs in is the lowest that admits it', () {
    final players = [rated(1500, id: 'low'), rated(1750, id: 'mid')];
    final e = tuesday(players: players);
    expect(sectionByRating(e, players[0])!.id, 'u1510');
    // 1750 is in the Open by right of the play-up rule; U1910 also admits
    // them and is where their rating puts them.
    expect(sectionByRating(e, players[1])!.id, 'u1910');
    expect(sectionRangeProblems(e, e.sections.first).keys, ['low']);
  });

  test('the play-up limit survives a save and reads in History', () {
    final e = tuesday();
    expect(Event.decode(e.encode()).playUpLimit, 200);
    expect(Event.decode(tuesday(playUp: 0).encode()).playUpLimit, 0);
    expect(tuesday(playUp: 0).toJson().containsKey('playUpLimit'), isFalse);
  });
}
