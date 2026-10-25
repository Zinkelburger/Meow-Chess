import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/team_report_dialog.dart';
import 'package:meow_chess/ui/workspace_actions.dart';
import '../support.dart';

void main() {
  testWidgets(
    'accelerated Swiss preview applies, persists, and can be cleared',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = fixture(count: 6);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => WorkspaceActions(
                  context,
                  c,
                ).sectionSettings(c.event!.sections.single.id),
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final preset = find.byKey(const ValueKey('field-accelerationPreset'));
      await tester.ensureVisible(preset);
      await tester.tap(preset);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Top half: +1 point in rounds 1–2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Review accelerated Swiss setup'), findsOneWidget);
      expect(c.event!.sections.single.acceleration, isEmpty);
      expect(find.textContaining('Player 00 (2000)'), findsOneWidget);
      await tester.tap(find.text('Apply acceleration'));
      await tester.pumpAndSettle();
      expect(c.repository.load()!.sections.single.acceleration, {
        'p0': [2, 2],
        'p1': [2, 2],
        'p2': [2, 2],
      });
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(preset);
      await tester.tap(preset);
      await tester.pumpAndSettle();
      await tester.tap(find.text('None (clear the schedule)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.event!.sections.single.acceleration, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'optional player fields validate and save without replacing pairing rating',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final panelKey = GlobalKey<PlayerPanelState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => PlayerPanel(
                key: panelKey,
                controller: c,
                player: c.event!.players.first,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('More player details'));
      await tester.tap(find.text('More player details'));
      await tester.pumpAndSettle();
      for (final field in {
        'club': 'City Club',
        'school': 'Lincoln',
        'grade': '6',
        'title': 'wfm',
        'fideId': '1234567',
        'fideRating': '2100',
        'federation': 'usa',
        'birthDate': '2014-02-30',
      }.entries) {
        final target = find.byKey(ValueKey('panel-${field.key}'));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.enterText(target, field.value);
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Birth date must be a valid YYYY-MM-DD date.'),
        findsOneWidget,
      );
      expect(c.event!.players.first.title, '');
      final birth = find.byKey(const ValueKey('panel-birthDate'));
      await tester.ensureVisible(birth);
      await tester.pumpAndSettle();
      await tester.tap(birth);
      await tester.pumpAndSettle();
      await tester.enterText(birth, '2014-02-28');
      expect(panelKey.currentState!.values['birthDate'], '2014-02-28');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final p = c.repository.load()!.players.first;
      expect(
        p.title,
        'WFM',
        reason:
            '${panelKey.currentState!.values} / ${panelKey.currentState!.error}',
      );
      expect(p.federation, 'USA');
      expect(p.school, 'Lincoln');
      expect(p.club, 'City Club');
      expect(p.fideRating, 2100);
      expect(p.rating, 2000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'team report changes scorer policy and exports the selected section',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      c.assignTeam(c.event!.players.map((p) => p.id), 'Owls');
      String saved = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TeamReportDialog(
              event: c.event!,
              sectionId: c.event!.sections.first.id,
              save: (name, bytes) async {
                saved = utf8.decode(bytes);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('team-scorers')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Best 2 per team').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('(2 scorers)'), findsOneWidget);
      await tester.tap(find.text('Save CSV'));
      await tester.pumpAndSettle();
      expect(saved, contains('Best 2 unique players'));
      expect(saved, contains('Player 00'));
      expect(saved, isNot(contains('Player 04')));
      expect(tester.takeException(), isNull);
    },
  );
}
