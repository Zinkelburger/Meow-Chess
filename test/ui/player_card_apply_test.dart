import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/player_panel.dart';
import 'package:meow_chess/ui/players_view.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

/// The Players page in a window, with a switch that takes the page away
/// the way choosing another page does.
Future<ValueNotifier<bool>> mountPlayers(
  WidgetTester tester,
  TournamentController c,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final shown = ValueNotifier(true);
  addTearDown(shown.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([c, shown]),
          builder: (_, _) => shown.value
              ? PlayersView(controller: c)
              : const Text('Another page'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shown;
}

Future<void> openCard(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('player-$id')));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String field, String value) async {
  await tester.enterText(find.byKey(ValueKey('panel-$field')), value);
  await tester.pump();
}

String fieldText(WidgetTester tester, String field) => tester
    .widget<TextField>(find.byKey(ValueKey('panel-$field')))
    .controller!
    .text;

/// The roster row's text for [id], where the saved rating shows.
Finder inRow(String id, String text) => find.descendant(
  of: find.byKey(ValueKey('player-$id')),
  matching: find.text(text),
);

const notice = ValueKey('undo-notice');

void main() {
  testWidgets('opening another player saves the edit as one step, with Undo', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    await openCard(tester, 'p0');
    await type(tester, 'rating', '1234');
    await type(tester, 'state', 'MA');
    // Typed, not yet saved.
    expect(c.event!.player('p0').rating, 2000);
    final head = c.graph.head;

    await openCard(tester, 'p1');
    expect(c.event!.player('p0').rating, 1234);
    expect(c.event!.player('p0').state, 'MA');
    expect(inRow('p0', '1234'), findsOneWidget);
    expect(fieldText(tester, 'name'), 'Player 01');
    expect(find.byKey(notice), findsOneWidget);
    expect(find.text('Saved Player 00’s changes'), findsOneWidget);
    expect(c.workspaceState.read('draft-player-p0'), '');

    // One Undo takes the whole edit back.
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').rating, 2000);
    expect(c.event!.player('p0').state, '');
    expect(c.graph.head, head);
    expect(inRow('p0', '2000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the card saves the edit, by the button or Esc', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    await openCard(tester, 'p0');
    await type(tester, 'rating', '1500');
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsNothing);
    expect(c.event!.player('p0').rating, 1500);
    expect(find.text('Saved Player 00’s changes'), findsOneWidget);

    await openCard(tester, 'p2');
    await type(tester, 'name', 'Jamie Patel');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsNothing);
    expect(c.event!.player('p2').name, 'Jamie Patel');
    expect(find.text('Saved Jamie Patel’s changes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an edit that cannot be saved keeps the card open on its error', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    await openCard(tester, 'p0');
    await type(tester, 'rating', 'strong');
    final revision = c.event!.revision;

    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'name'), 'Player 00');
    expect(find.byKey(const ValueKey('panel-error')), findsOneWidget);
    expect(find.text('Enter a rating number, or UNR.'), findsOneWidget);
    expect(c.event!.revision, revision);
    expect(find.byKey(notice), findsNothing);

    // Another player does not replace it either.
    await openCard(tester, 'p1');
    expect(fieldText(tester, 'name'), 'Player 00');
    expect(fieldText(tester, 'rating'), 'strong');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'name'), 'Player 00');
    expect(c.event!.revision, revision);

    // Discard draft is how the edit is thrown away; then the card closes.
    await tester.ensureVisible(find.text('Discard draft'));
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'rating'), '2000');
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsNothing);
    expect(c.event!.revision, revision);
    expect(find.byKey(notice), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a discarded edit is not saved when the card closes', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    await openCard(tester, 'p0');
    await type(tester, 'rating', '1111');
    await tester.ensureVisible(find.text('Discard draft'));
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    final revision = c.event!.revision;
    await openCard(tester, 'p1');
    expect(fieldText(tester, 'name'), 'Player 01');
    expect(c.event!.revision, revision);
    expect(c.event!.player('p0').rating, 2000);
    expect(find.byKey(notice), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Add form keeps a half-typed player as a draft', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await mountPlayers(tester, c);
    final count = c.event!.players.length, revision = c.event!.revision;
    await tester.tap(find.text('Add player'));
    await tester.pumpAndSettle();
    await type(tester, 'name', 'Walk Up');
    await type(tester, 'rating', '1400');

    // Closing, or opening a player, registers nobody.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsNothing);
    await openCard(tester, 'p0');
    expect(fieldText(tester, 'name'), 'Player 00');
    expect(c.event!.players.length, count);
    expect(c.event!.revision, revision);
    expect(find.byKey(notice), findsNothing);

    await tester.tap(find.text('Add player'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'name'), 'Walk Up');
    expect(fieldText(tester, 'rating'), '1400');
    expect(find.text('Draft saved · not applied'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the page saves a valid edit and parks an invalid one', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final shown = await mountPlayers(tester, c);
    await openCard(tester, 'p0');
    await type(tester, 'rating', '1777');
    shown.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Another page'), findsOneWidget);
    expect(c.event!.player('p0').rating, 1777);
    expect(find.text('Saved Player 00’s changes'), findsOneWidget);
    expect(c.workspaceState.read('draft-player-p0'), '');
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').rating, 2000);

    // The page comes back on the same card, with nothing waiting.
    shown.value = true;
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'rating'), '2000');
    expect(find.text('Draft saved · not applied'), findsNothing);

    // What cannot be saved is never applied; it waits on the player's card.
    await type(tester, 'rating', 'strong');
    final revision = c.event!.revision;
    shown.value = false;
    await tester.pumpAndSettle();
    expect(c.event!.revision, revision);
    shown.value = true;
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'rating'), 'strong');
    expect(find.text('Draft saved · not applied'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('notes under the card fields wrap at ${scale}x text', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: PlayerPanel(
                controller: c,
                player: c.event!.player('p0'),
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final note = find.text(PlayerPanelState.ratingLockedNote);
      expect(note, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(note);
      expect(paragraph.didExceedMaxLines, false);
      // The whole sentence is laid out, on as many lines as it needs.
      if (scale == 2) {
        expect(
          paragraph.size.height,
          greaterThan(paragraph.preferredLineHeight * 1.5),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the computer checkbox has a plain label', (tester) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: PlayerPanel(
            controller: c,
            player: c.event!.player('p0'),
            onClose: () {},
          ),
        ),
      ),
    );
    await openPanelGroup(tester, 'assigned');
    await tester.pumpAndSettle();
    expect(find.text('Computer entrant'), findsOneWidget);
    expect(find.textContaining('Computer entrant (rule'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
