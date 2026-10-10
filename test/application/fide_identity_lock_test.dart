import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/member_observation.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/section_panel.dart';

import '../support.dart';

void main() {
  group('FIDE registration', () {
    test('reads and writes the stored keys', () {
      const json = {
        'federation': 'USA',
        'chiefArbiter': 'Ada Arbiter',
        'chiefArbiterId': '2000001',
        'deputies': [
          {'name': 'Bo Deputy', 'id': '2000002'},
        ],
      };
      final fide = FideRegistration.fromJson(json);
      expect(
        fide.chiefArbiter,
        const FideOfficial(name: 'Ada Arbiter', id: '2000001'),
      );
      expect(fide.deputies.single.name, 'Bo Deputy');
      expect(fide.toJson(), json);
      expect(FideRegistration.fromJson(null).isEmpty, isTrue);
      expect(const FideRegistration().reportFederation, 'USA');
    });

    test('refuses malformed deputies with a message, not a type error', () {
      for (final deputies in [
        {'name': 'Bo'},
        'Bo Deputy',
        ['Bo Deputy'],
      ]) {
        expect(
          () => FideRegistration.fromJson({'deputies': deputies}),
          throwsA(
            isA<TournamentException>().having(
              (e) => e.message,
              'message',
              contains('Deputy arbiters are a list'),
            ),
          ),
        );
      }
    });
  });

  group('US Chess FIDE identity', () {
    test('reads every gender spelling US Chess uses', () {
      for (final (gender, sex) in [
        ('Male', 'm'),
        ('M', 'm'),
        ('Female', 'w'),
        ('F', 'w'),
        ('W', 'w'),
        ('', null),
        (null, null),
      ]) {
        expect(sexFromUsChessGender(gender), sex, reason: '$gender');
      }
    });

    test('fills blanks only, and replaces the ID only when asked', () {
      final player = Player(id: 'a', name: 'A', fideId: '1111', title: 'FM');
      final filled = withUsChessFideIdentity(
        player,
        fideId: '2222',
        fideTitle: 'G',
        fideCountry: 'USA',
        gender: 'F',
      );
      expect(filled.fideId, '1111');
      expect(filled.title, 'FM');
      expect(filled.federation, 'USA');
      expect(filled.sex, 'w');
      expect(
        withUsChessFideIdentity(
          player,
          fideId: '2222',
          replaceFideId: true,
        ).fideId,
        '2222',
      );
    });
  });

  test('a FIDE section moved to a ladder keeps the TD\'s Not rated', () {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final section = c.event!.sections.single.copy(
      fideRated: true,
      unrated: true,
    );
    Section moveToLadder({required bool notRated}) =>
        applySectionValues(c.event!, section, {
          ...sectionValues(section),
          'format': Format.ladder.name,
          extensionKey(Format.ladder, 'unrated'): '$notRated',
        });
    final unrated = moveToLadder(notRated: true);
    expect(unrated.fideRated, isFalse);
    expect(unrated.unrated, isTrue);
    expect(moveToLadder(notRated: false).unrated, isFalse);
  });

  test('FIDE ratings cannot change once the FIDE section is paired', () async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final e = c.event!;
    c.change(
      'FIDE',
      e.copy(
        players: [
          for (final p in e.players)
            p.copy(fideId: '1${p.memberId}', fideStandard: 1800),
        ],
        sections: [e.sections.single.copy(fideRated: true)],
      ),
    );
    final p0 = c.event!.player('p0');
    expect(fideRatingsLocked(c.event!, p0), isFalse);
    c.savePlayer(p0.copy(fideStandard: 1850));

    final batch = await c.propose();
    expect(batch.issues, isEmpty);
    c.post(batch);
    final paired = c.event!.player('p0');
    expect(fideRatingsLocked(c.event!, paired), isTrue);
    expect(
      () => c.savePlayer(paired.copy(fideStandard: 1900)),
      throwsA(isA<TournamentException>()),
    );
    expect(c.event!.player('p0').fideStandard, 1850);
    // Other edits still save.
    c.savePlayer(paired.copy(notes: 'arrived late'));
    expect(c.event!.player('p0').notes, 'arrived late');
  });
}
