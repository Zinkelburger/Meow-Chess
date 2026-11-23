import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/announcement.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/infrastructure/web_roster.dart';
import 'package:meow_chess/ui/notes_panel.dart';
import 'package:meow_chess/ui/setup_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/update_panels.dart';
import 'package:meow_chess/ui/workspace.dart';

/// A Tornado entry list: eight in the Open (one of them rated 1502), four
/// in U1800, and two notes.
const entries = [
  ('Avery Stone', '2104', '30000001', 'Open', ''),
  ('Blake Rivera', '1987', '30000002', 'Open', 'Bye rd 1'),
  ('Casey Wu', '1902', '30000003', 'Open', ''),
  ('Devon Hale', '1856', '30000004', 'Open', ''),
  ('Emery Park', '1811', '30000005', 'Open', ''),
  ('Finley Ortiz', '1740', '30000006', 'Open', ''),
  ('Gray Novak', '1655', '30000007', 'Open', ''),
  ('Harper Lin', '1502', '30000008', 'Open', ''),
  ('Indigo Shah', '1766', '30000009', 'U1800', ''),
  ('Jules Kim', '1690', '30000010', 'U1800', 'Leaving after round 3'),
  ('Kai Moreno', '1602', '30000011', 'U1800', ''),
  ('Perry Vance', 'UNR', '', 'U1800', ''),
];

String table() => [
  '<table><thead><tr><th>#</th><th>Name</th><th>Rating</th>',
  '<th>USCF ID</th><th>Section</th><th>Byes</th></tr></thead><tbody>',
  for (final (i, (name, rating, id, section, note)) in entries.indexed)
    '<tr><td>${i + 1}</td><td>$name</td><td>$rating</td><td>$id</td>'
        '<td>$section</td><td>$note</td></tr>',
  '</tbody></table>',
].join();

const tornado = Announcement(
  rounds: 4,
  format: Format.swiss,
  timeControl: 'G/60 d5',
  playUpLimit: 200,
  mergeBelow: 8,
);

const url = 'https://boylstonchess.org/events/1600/tornado-151';

TournamentController newEvent() =>
    TournamentController(SqliteEventRepository(':memory:'))
      ..create('Tornado 151');

/// The Tornado list imported, with or without an event page to read.
TournamentController imported({Announcement? announcement}) {
  final c = newEvent();
  final review = RosterReview(
    c.event!,
    url,
    parseWebRoster(table()),
    announcement: announcement,
  );
  c.change(
    'Import',
    review.apply(c.event!, review.changes.map((r) => r.key).toSet()),
  );
  return c;
}

Future<void> mount(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: Align(alignment: Alignment.topRight, child: panel),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Section section(TournamentController c, String name) =>
    c.event!.sections.firstWhere((s) => s.name == name);

void main() {
  testWidgets('importing from a URL is one count and one button', (
    tester,
  ) async {
    final c = newEvent();
    addTearDown(c.dispose);
    var importedWith = <bool>[];
    await mount(
      tester,
      WebRosterPanel(
        controller: c,
        onClose: () {},
        loader: (_) async => parseWebRoster(table()),
        announcementLoader: (_) async => tornado,
        onImported: importedWith.add,
      ),
    );
    // Before fetching there is only the URL and the button.
    expect(find.byKey(const ValueKey('import-refresh-ratings')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('roster-url')), url);
    await tester.tap(find.text('Fetch players'));
    await tester.pumpAndSettle();
    expect(find.text('12 players'), findsOneWidget);
    expect(find.text('Open 8 · U1800 4'), findsOneWidget);
    expect(find.text('Event page: 4 rounds · G/60 d5'), findsOneWidget);
    // No rounds question and no list to scroll: the entries stay folded.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Avery Stone'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('web-show-all')));
    await tester.pumpAndSettle();
    expect(find.text('Avery Stone'), findsOneWidget);
    expect(find.text('1502 · Open'), findsOneWidget);

    await tester.tap(find.text('Add 12 players'));
    await tester.pumpAndSettle();
    final e = c.event!;
    expect(e.players, hasLength(12));
    expect(importedWith, [true]);
    expect(e.timeControl, 'G/60 d5');
    expect(e.playUpLimit, 200);
    expect(section(c, 'Open').plannedRounds, 4);
    expect(section(c, 'Open').roundsUnset, isFalse);
    expect(section(c, 'U1800').ratingCeiling, 1800);
    expect(find.text('Added 12 players. Nobody was removed.'), findsOneWidget);
    // One step to take back.
    c.undo();
    expect(c.event!.players, isEmpty);
    expect(c.event!.sections, isEmpty);
  });

  testWidgets('a refresh lists only what changed, unticked', (tester) async {
    final c = imported(announcement: tornado);
    addTearDown(c.dispose);
    final rows = table()
        .replaceFirst('<td>1987</td>', '<td>2001</td>')
        .replaceFirst(
          '</tbody>',
          '<tr><td>13</td><td>Quinn Late</td><td>1450</td><td>30000020</td>'
              '<td>U1800</td><td></td></tr></tbody>',
        );
    await mount(
      tester,
      WebRosterPanel(
        controller: c,
        onClose: () {},
        loader: (_) async => parseWebRoster(rows),
      ),
    );
    await tester.tap(find.text('Fetch updates'));
    await tester.pumpAndSettle();
    expect(find.text('1 new player'), findsOneWidget);
    expect(find.text('U1800 +1'), findsOneWidget);
    expect(find.text('Changed on the website'), findsOneWidget);
    expect(find.text('Update Blake Rivera'), findsOneWidget);
    expect(find.text('Rating 1987 → 2001'), findsOneWidget);
    expect(find.text('Add 1 player'), findsOneWidget);
    final blake = c.event!.players.firstWhere((p) => p.name == 'Blake Rivera');
    // Ticked by the director, never by default.
    await tester.tap(find.text('Update Blake Rivera'));
    await tester.pump();
    await tester.tap(find.text('Add 1 and update 1'));
    await tester.pumpAndSettle();
    expect(c.event!.players, hasLength(13));
    expect(c.event!.player(blake.id).rating, 2001);
    expect(section(c, 'U1800').players, hasLength(5));
  });

  testWidgets('Set up takes the rounds once for every section', (tester) async {
    final c = imported();
    addTearDown(c.dispose);
    expect(c.event!.sections.every((s) => s.roundsUnset), isTrue);
    // Nothing is paired until the rounds are in, and the page says why.
    final blocked = postState(c.event!, null);
    expect(blocked.label, isNull);
    expect(blocked.why, '2 sections have no rounds set.');
    expect(blocked.setUp, isTrue);
    expect(proposeRounds(c.event!, null, true).rounds, isEmpty);
    expect(
      proposeRounds(
        c.event!,
        section(c, 'Open').id,
        false,
      ).issues.values.single,
      'Set the number of rounds for Open before pairing it.',
    );

    await mount(tester, SetupPanel(controller: c, onClose: () {}));
    // Said once under the table, not on every row.
    expect(
      find.text('A section is not paired until its rounds are set.'),
      findsOneWidget,
    );
    expect(find.textContaining('8 players'), findsOneWidget);
    expect(find.textContaining('4 players · under 1800'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('set-up-every-rounds')),
      '4',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('set-up-time-control')),
      'G/60 d5',
    );
    await tester.enterText(find.byKey(const ValueKey('set-up-play-up')), '200');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-set-up')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('set-up-saved')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-up-unset')), findsNothing);
    // The event's Rounds field goes on saying what the sections say.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('set-up-every-rounds')))
          .controller!
          .text,
      '4',
    );
    final e = c.event!;
    expect(e.sections.map((s) => (s.plannedRounds, s.roundsUnset)), [
      (4, false),
      (4, false),
    ]);
    expect(e.timeControl, 'G/60 d5');
    expect(e.playUpLimit, 200);
    expect(postState(e, null).label, 'Create pairings · Round 1 · 2 sections');
    expect(postState(e, null).setUp, isFalse);
    // The consequence of the play-up limit is stated.
    expect(find.text('Open: 1600 and over'), findsOneWidget);
    // One step.
    c.undo();
    expect(c.event!.sections.every((s) => s.roundsUnset), isTrue);
  });

  testWidgets('Set up says what the event page announced, and a bad value '
      'stays on its field', (tester) async {
    final c = imported(announcement: tornado);
    addTearDown(c.dispose);
    await mount(tester, SetupPanel(controller: c, onClose: () {}));
    // Already as announced: it says so, and there is nothing to press.
    expect(find.text('Matches the event page'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-up-use-announced')), findsNothing);
    expect(find.byKey(const ValueKey('save-set-up')), findsNothing);
    // U1800 has four players and the page merges sections under eight:
    // that is said beside Create pairings, not as a mark on the row.
    final u1800 = section(c, 'U1800');
    expect(find.textContaining('may be merged'), findsNothing);
    // Four players cannot play four rounds without meeting twice, which
    // matters more than the page's merge size; with three rounds it is the
    // page's size that is quoted.
    expect(
      postState(c.event!, null).caution,
      'U1800 has 4 players for 4 rounds, so some will meet twice.',
    );
    expect(
      tooFewPlayers(c.event!, u1800.copy(plannedRounds: 3)),
      'U1800 has 4 players; the event page says under 8 may be merged.',
    );
    expect(tooFewPlayers(c.event!, section(c, 'Open')), isNull);
    await tester.enterText(
      find.byKey(ValueKey('set-up-rounds-${u1800.id}')),
      '40',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-set-up')));
    await tester.pumpAndSettle();
    expect(
      find.text('Number of rounds must be between 1 and 32.'),
      findsOneWidget,
    );
    expect(section(c, 'U1800').plannedRounds, 4);
    // Now that the fields differ, the page's values are named and offered,
    // and the event's Rounds field says the sections no longer agree.
    expect(
      find.text(
        'Event page: 4\u00a0rounds · G/60\u00a0d5 · '
        'play\u00a0up\u00a0within\u00a0200',
      ),
      findsOneWidget,
    );
    expect(find.text('Varies'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set-up-use-announced')));
    await tester.pump();
    expect(find.byKey(const ValueKey('save-set-up')), findsNothing);
  });

  testWidgets('a player rated too low to play up is moved or kept in one '
      'press', (tester) async {
    final c = imported(announcement: tornado);
    addTearDown(c.dispose);
    final harper = c.event!.players.firstWhere((p) => p.name == 'Harper Lin');
    await mount(tester, SetupPanel(controller: c, onClose: () {}));
    expect(find.text('Players to check'), findsOneWidget);
    expect(
      find.text(
        'Rated 1502: playing up into Open takes 1600 or more, within 200 '
        'points of the U1800 cap.',
      ),
      findsOneWidget,
    );
    // The unrated player in U1800 and the 1655 in the Open are fine.
    expect(find.byKey(ValueKey('set-up-flag-${harper.id}')), findsOneWidget);
    // The section's own row counts them, since the list is below it.
    expect(
      find.byKey(ValueKey('set-up-to-check-${section(c, 'Open').id}')),
      findsOneWidget,
    );
    expect(find.text('1 to check'), findsOneWidget);
    expect(find.textContaining('Move to'), findsOneWidget);
    // Pairing is not held back for it.
    expect(postState(c.event!, null).label, isNotNull);

    await tester.tap(find.text('Keep in Open'));
    await tester.pumpAndSettle();
    expect(section(c, 'Open').rangeExceptions.keys, [harper.id]);
    expect(find.text('Players to check'), findsNothing);
    c.undo();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to U1800'));
    await tester.pumpAndSettle();
    expect(c.event!.sectionOf(harper.id)!.name, 'U1800');
    expect(section(c, 'Open').players, hasLength(7));
    expect(find.text('Players to check'), findsNothing);
  });

  testWidgets('registration notes are worked through with the bye grid', (
    tester,
  ) async {
    final c = imported(announcement: tornado);
    addTearDown(c.dispose);
    final blake = c.event!.players.firstWhere((p) => p.name == 'Blake Rivera');
    final jules = c.event!.players.firstWhere((p) => p.name == 'Jules Kim');
    expect(waitingNotes(c.event!).map((p) => p.name), [
      'Blake Rivera',
      'Jules Kim',
    ]);
    await mount(tester, NotesPanel(controller: c, onClose: () {}));
    expect(find.text('Bye rd 1'), findsOneWidget);
    expect(find.text('Leaving after round 3'), findsOneWidget);
    // Nothing is read out of a note: the director gives the bye.
    expect(c.event!.player(blake.id).byes, isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('note-${blake.id}')),
        matching: find.byKey(const ValueKey('bye-1-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.event!.player(blake.id).byes, {1: 1});
    await tester.tap(find.byKey(ValueKey('note-done-${blake.id}')));
    await tester.pumpAndSettle();
    expect(c.event!.player(blake.id).noteWaiting, isFalse);
    expect(find.byKey(ValueKey('note-${blake.id}')), findsNothing);
    expect(find.byKey(ValueKey('note-${jules.id}')), findsOneWidget);
    // Dealt-with notes fold away and can be reopened.
    await tester.tap(find.byKey(const ValueKey('notes-done-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('note-reopen-${blake.id}')));
    await tester.pumpAndSettle();
    expect(c.event!.player(blake.id).noteWaiting, isTrue);
    // A note the website changes asks to be read again.
    c.markNoteHandled(blake.id);
    c.savePlayer(
      c.event!.player(blake.id).copy(registrationNote: 'Bye rd 1 and 2'),
    );
    expect(c.event!.player(blake.id).noteWaiting, isTrue);
    expect(
      Event.decode(c.event!.encode()).player(jules.id).noteWaiting,
      isTrue,
    );
  });

  testWidgets('an import in the workspace hands on to Set up, then notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = newEvent();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Workspace(
          controller: c,
          path: ':memory:',
          onClose: () {},
          onTheme: () {},
          rosterLoader: (_) async => parseWebRoster(table()),
          announcementLoader: (_) async => tornado,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('set-up-sections')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-from-url')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('roster-url')), url);
    await tester.tap(find.text('Fetch players'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-refresh-ratings')));
    await tester.pump();
    await tester.tap(find.text('Add 12 players'));
    await tester.pumpAndSettle();
    // Set up opens by itself, already holding what the page announced.
    expect(find.byKey(const ValueKey('set-up')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-up-sections')), findsOneWidget);
    expect(find.text('Players to check'), findsOneWidget);
    expect(find.text('Review 2 registration notes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set-up-notes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('registration-notes')), findsOneWidget);
    expect(find.text('Bye rd 1'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('notes-close')));
    await tester.pumpAndSettle();
    // The Set up button brings the panel back at any time.
    await tester.tap(find.byKey(const ValueKey('set-up-sections')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('set-up')), findsOneWidget);
    // One Combine under the table, on no section's row, opens the panel
    // for any of them and returns here.
    final all = find.byKey(const ValueKey('set-up-combine'));
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.text('Combine sections'), findsOneWidget);
    expect(find.text('U1800 into Open'), findsOneWidget);
    expect(find.text('Open into U1800'), findsOneWidget);
    // The Open takes everyone's rating, so it is the one offered to stay.
    expect(find.text('Combine into Open · 12 players'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('combine-confirm')));
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.name, 'Open');
    expect(c.event!.sections.single.players, hasLength(12));
    expect(find.byKey(const ValueKey('set-up')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
