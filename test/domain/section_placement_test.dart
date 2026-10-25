import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/section_placement.dart';

Event scholastics({List<Section> sections = const []}) => Event(
  id: 'e',
  name: 'November Scholastics',
  date: '2026-11-15',
  players: [
    for (var i = 0; i < 6; i++) Player(id: 'k$i', name: 'Kid $i', rating: 900),
  ],
  sections: sections,
);

void main() {
  test('labels match ignoring case, spacing, punctuation and "Under" as U', () {
    for (final label in ['Under 1000', 'U1000', 'u-1000', ' under1000 ']) {
      expect(sectionKey(label), 'u1000', reason: label);
    }
    expect(sectionKey('Championship'), sectionKey('CHAMPIONSHIP '));
    expect(sectionKey('Under 500'), isNot(sectionKey('Under 1000')));
    // "Under" only shortens before a rating.
    expect(sectionKey('Under Twelve'), 'undertwelve');
  });

  test('labels join unpaired sections, start new ones, or say why not', () {
    final event = scholastics(
      sections: [
        Section(id: 'u1000', name: 'Under 1000', players: const []),
        Section(
          id: 'champ',
          name: 'Championship',
          players: const ['k5'],
          rounds: [Round(number: 1, games: const [])],
        ),
      ],
    );
    final plan = planSections(event, {
      'k0': 'U1000',
      'k1': 'Under 500',
      'k2': 'under 500',
      'k3': 'Championship',
      'k4': '',
      // Already placed: stays where they are.
      'k5': 'Under 1000',
    });
    expect(plan.joins, {'k0': 'u1000'});
    expect(plan.creates, {
      'Under 500': ['k1', 'k2'],
    });
    expect(plan.createdFor('k2'), 'Under 500');
    expect(plan.skipped.keys, ['k3']);
    expect(plan.skipped['k3'], contains('already paired'));
  });

  test('two sections with the same key are ambiguous, never guessed', () {
    final event = scholastics(
      sections: [
        Section(id: 'a', name: 'U1000', players: const []),
        Section(id: 'b', name: 'Under 1000', players: const []),
      ],
    );
    final plan = planSections(event, {'k0': 'Under 1000'});
    expect(plan.isEmpty, isTrue);
    expect(plan.skipped['k0'], contains('2 sections match'));
  });

  test('new sections are Swiss on the next free boards; a section that '
      'grows into another\'s boards moves after them', () {
    final event = scholastics(
      sections: [
        Section(
          id: 'a',
          name: 'Championship',
          players: const ['k0', 'k1'],
          boardStart: 1,
        ),
        Section(
          id: 'b',
          name: 'Under 1000',
          players: const ['k5'],
          boardStart: 2,
        ),
      ],
    );
    final plan = planSections(event, {
      'k2': 'Championship',
      'k3': 'Championship',
      'k4': 'Under 500',
    });
    final placed = applySectionPlan(event, plan, rounds: 4, newId: () => 'new');
    final champ = placed.sections.firstWhere((s) => s.id == 'a');
    expect(champ.players, ['k0', 'k1', 'k2', 'k3']);
    // Two boards from 1 would take Under 1000's board 2.
    expect(champ.boardStart, 3);
    expect(placed.sections.firstWhere((s) => s.id == 'b').boardStart, 2);
    final created = placed.sections.firstWhere((s) => s.id == 'new');
    expect(created.name, 'Under 500');
    expect(created.format, Format.swiss);
    expect(created.plannedRounds, 4);
    expect(created.players, ['k4']);
    expect(created.boardStart, 5);
  });

  test('without rounds no section is created and nobody is lost', () {
    final event = scholastics();
    final plan = planSections(event, {'k0': 'Under 500'});
    final placed = applySectionPlan(event, plan, rounds: 0, newId: () => 'x');
    expect(placed.sections, isEmpty);
    expect(placed.players, hasLength(6));
    expect(
      () => applySectionPlan(event, plan, rounds: 40, newId: () => 'x'),
      throwsA(isA<TournamentException>()),
    );
  });
}
