import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

Future<void> mount(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Workspace(
        controller: c,
        path: ':memory:',
        onClose: () {},
        onTheme: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every piece of text on screen, with its font size.
Iterable<(String, double)> textSizes(WidgetTester tester) sync* {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final sizes = <double>[];
    paragraph.text.visitChildren((span) {
      final size = span.style?.fontSize;
      if (size != null && span is TextSpan && (span.text ?? '').trim() != '') {
        sizes.add(size);
      }
      return true;
    });
    for (final size in sizes) {
      yield (paragraph.text.toPlainText(), size);
    }
  }
}

void main() {
  testWidgets('the status bar says when it saved and opens backups', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('status-bar')),
        matching: find.textContaining('Event saved '),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Revision ${c.event!.revision}'),
      findsOneWidget,
    );
    expect(find.text('No backup folder'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('status-backup')));
    await tester.pumpAndSettle();
    expect(find.text('Choose folder…'), findsOneWidget);
    // Backups no longer hide behind the event-name pencil, and the event
    // panel takes the dock's place rather than squeezing the page.
    await tester.tap(find.byKey(const ValueKey('event-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-name')), findsOneWidget);
    expect(find.text('Choose folder…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a practice copy has its own banner', (tester) async {
    final c = fixture(practice: true);
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.byKey(const ValueKey('practice-banner')), findsOneWidget);
    expect(find.text('Practice copy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('undo names its step in words', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final g = c.event!.games.first;
    c.recordResult(g.id, Outcome.draw);
    await mount(tester, c);
    expect(find.text('Undo Result, board ${g.board}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pumpAndSettle();
    expect(c.event!.games.first.outcome, Outcome.unreported);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tab to a name on Rounds, then Enter opens player details', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c);
    await tester.tap(find.text('Rounds').first);
    await tester.pumpAndSettle();
    final g = c.event!.sections.first.rounds.last.games.first;
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('panel-name')))
          .controller!
          .text,
      c.event!.player(g.white).name,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no text on the main pages is smaller than 12px', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    c.recordResult(c.event!.games.first.id, Outcome.draw);
    await mount(tester, c);
    await tester.tap(find.byTooltip('History (Ctrl+H)'));
    await tester.pumpAndSettle();
    for (final page in ['Players', 'Rounds', 'Reports']) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      for (final (text, size) in textSizes(tester)) {
        expect(size, greaterThanOrEqualTo(12), reason: '$page: "$text"');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the theme choice survives a restart', (tester) async {
    final directory = Directory.systemTemp.createTempSync('meow-settings-');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.tap(find.byTooltip('Dark mode'));
    await tester.pump();
    expect(
      jsonDecode(File('${directory.path}/settings.json').readAsStringSync()),
      {'theme': 'dark'},
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pump();
    expect(find.byTooltip('Light mode'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
