import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/member_identity_lookup.dart';

const candidate = MemberObservation(
  id: '00123456',
  name: 'Test Member',
  state: 'MA',
  retrievedAt: '2026-10-03',
  ratings: {'R': 1500},
);

void main() {
  late TextEditingController id, name;
  setUp(() {
    id = TextEditingController(text: '12345678');
    name = TextEditingController(text: 'Test Member');
  });
  tearDown(() {
    id.dispose();
    name.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    required Future<MemberObservation?> Function(String) lookup,
    required Future<List<MemberObservation>> Function(String) search,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MemberIdentityLookup(
            id: id,
            name: name,
            lookup: lookup,
            search: search,
            onSelected: (member) => id.text = member.id,
          ),
        ),
      ),
    ),
  );

  testWidgets('missing ID suggests candidates and changes only on selection', (
    tester,
  ) async {
    await show(
      tester,
      lookup: (_) async => throw const MemberNotFound(),
      search: (query) async {
        expect(query, 'Test Member');
        return [candidate];
      },
    );
    await tester.tap(find.text('Check ID'));
    await tester.pumpAndSettle();
    expect(find.textContaining('was not found'), findsOneWidget);
    expect(find.textContaining('MA · Regular 1500'), findsOneWidget);
    expect(id.text, '12345678');
    await tester.tap(find.text('Use 00123456'));
    await tester.pumpAndSettle();
    expect(id.text, '00123456');
    expect(name.text, 'Test Member');
    expect(find.textContaining('Save to apply'), findsOneWidget);
  });
  testWidgets('syntax errors warn without a request and suggest by name', (
    tester,
  ) async {
    id.text = '123';
    await show(
      tester,
      lookup: (_) async => fail('Invalid ID sent'),
      search: (_) async => [candidate],
    );
    expect(find.textContaining('Invalid ID format:'), findsOneWidget);
    await tester.tap(find.text('Check ID'));
    await tester.pumpAndSettle();
    expect(find.text('Use 00123456'), findsOneWidget);
  });
  testWidgets('another person at a valid ID triggers warning and suggestions', (
    tester,
  ) async {
    await show(
      tester,
      lookup: (value) async => MemberObservation(
        id: value,
        name: 'Someone Else',
        retrievedAt: '',
        ratings: const {},
      ),
      search: (_) async => [candidate],
    );
    await tester.tap(find.text('Check ID'));
    await tester.pumpAndSettle();
    expect(find.textContaining('belongs to Someone Else'), findsOneWidget);
    expect(find.text('Use 00123456'), findsOneWidget);
    expect(id.text, '12345678');
  });
  testWidgets('network failure stays unverified and does not search', (
    tester,
  ) async {
    await show(
      tester,
      lookup: (_) async => throw const TournamentException('HTTP 429'),
      search: (_) async => fail('Do not search on service failure'),
    );
    await tester.tap(find.text('Check ID'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ID could not be verified'), findsOneWidget);
    expect(find.textContaining('was not found'), findsNothing);
    expect(id.text, '12345678');
  });
  testWidgets('name order and punctuation do not create conflicts', (
    tester,
  ) async {
    id.text = candidate.id;
    name.text = 'MEMBER, Test';
    await show(
      tester,
      lookup: (_) async => candidate,
      search: (_) async => fail('Name already matches'),
    );
    await tester.tap(find.text('Check ID'));
    await tester.pumpAndSettle();
    expect(find.text('ID 00123456 is Test Member'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);
    expect(find.textContaining('.'), findsNothing);
  });
  testWidgets(
    'editing and changing back invalidates pending checks and search',
    (tester) async {
      final pending = Completer<MemberObservation?>();
      final results = Completer<List<MemberObservation>>();
      await show(
        tester,
        lookup: (_) => pending.future,
        search: (_) => results.future,
      );
      await tester.tap(find.text('Check ID'));
      await tester.pump();
      id.text = '87654321';
      id.text = '12345678';
      pending.completeError(const MemberNotFound());
      await tester.pumpAndSettle();
      expect(find.textContaining('was not found'), findsNothing);
      await tester.tap(find.text('Find by name'));
      await tester.pump();
      name.text = 'Another Person';
      results.complete([candidate]);
      await tester.pumpAndSettle();
      expect(find.text('Use 00123456'), findsNothing);
    },
  );
  testWidgets('previously rendered candidate cannot apply after editing', (
    tester,
  ) async {
    await show(
      tester,
      lookup: (_) async => candidate,
      search: (_) async => [candidate],
    );
    await tester.tap(find.text('Find by name'));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Use 00123456'),
    );
    name.text = 'Another Person';
    button.onPressed!();
    expect(id.text, '12345678');
    await tester.pumpAndSettle();
  });
}
