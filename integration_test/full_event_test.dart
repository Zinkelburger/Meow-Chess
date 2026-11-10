import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

import '../test/dbf_reader.dart';
import '../test/ui/workspace_host.dart';

/// A club Swiss from an empty event to the rating report, through the screens
/// a director uses: pasted entries with untidy rows, a section, three rounds
/// typed at the keyboard, a walk-up during round 1, a no-show who never had a
/// US Chess ID, a result typed over, and the three report files decoded.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a whole Swiss, from pasted entries to the rating report', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('meow-journey-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/Fall Open.meow';
    var c = TournamentController(SqliteEventRepository(path));
    // Registered before anything can fail, and reads the variable when it
    // runs: an open file would keep the folder above from being deleted on
    // Windows and hide the real failure behind that one.
    addTearDown(() => c.dispose());
    c.create('Fall Open');

    Finder k(String key) => find.byKey(ValueKey(key));
    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f.first);
      await tester.pumpAndSettle();
      await tester.tap(f.first);
      await tester.pumpAndSettle();
    }

    Section open() => c.event!.sections.single;
    Player named(String name) =>
        c.event!.players.firstWhere((p) => p.name == name);
    int points(String name) => standings(
      c.event!,
      open(),
    ).firstWhere((r) => r.player.name == name).points;

    /// Types [key] into the score box of [g]'s white player.
    Future<void> type(Game g, LogicalKeyboardKey key) async {
      await tap(k('score-${g.id}-w'));
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    /// Presses Create pairings and waits for the round to be posted. The
    /// engine runs on another isolate, so the frames can settle before the
    /// pairings arrive.
    Future<void> pairNext() async {
      final before = open().rounds.length;
      await tap(k('pair-next-round'));
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (open().rounds.length == before) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Round ${before + 1} was never paired');
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    /// The higher-rated player wins every board still without a result.
    Future<void> finishRound() async {
      for (final g in open().rounds.last.games) {
        if (g.outcome != Outcome.unreported) continue;
        final e = c.event!;
        await type(
          g,
          e.player(g.white).rating >= e.player(g.black).rating
              ? LogicalKeyboardKey.digit1
              : LogicalKeyboardKey.digit0,
        );
      }
      expect(open().rounds.last.games.every((g) => g.outcome.resolved), isTrue);
    }

    await mountWorkspace(tester, c, path: path, size: const Size(1440, 900));

    // Entries pasted from a spreadsheet, with the rows a real list has: a
    // provisional rating, an unrated player, a word where an ID belongs, a
    // repeated row and an empty one. Everyone named comes in.
    await tap(find.text('Paste'));
    await tester.enterText(
      k('paste-roster'),
      [
        'Name\tUSCF ID\tRating',
        'Carlsen, Magnus\t12345678\t2100',
        'Nakamura, Hikaru\t12345679\t2000',
        "O'Brien-Smith Jr., Seán\t12345680\t1900",
        'Müller, Jürgen\t12345681\t1800',
        'Li, Wei\t12345682\t1750',
        'Garcia, Maria\t12345683\t1650',
        'Patel, Anika\t12345684\t1500P12',
        'Kim, Daniel\t12345685\t1350',
        'Rookie, Unrated\t30000001\tUnr.',
        'Ghost, Noshow\tNEW\t1000',
        'Garcia, Maria\t12345683\t1650',
        '\t\t',
      ].join('\n'),
    );
    await tester.pumpAndSettle();
    await tap(find.text('Review import'));
    await tap(k('confirm-roster-import'));
    expect(c.event!.players, hasLength(10));
    expect(named('Patel, Anika').rating, 1500);
    expect(named('Rookie, Unrated').rating, 0);
    expect(named('Ghost, Noshow').memberId, isEmpty);

    // What the rating report needs about the event, entered once.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tap(k('event-details'));
    for (final (field, value) in [
      ('time', 'G/60 d5'),
      ('city', 'Cambridge'),
      ('state', 'MA'),
      ('zip', '02139'),
      ('td', '12000001'),
      ('affiliate', 'A6000220'),
    ]) {
      await tester.enterText(k('event-$field'), value);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.event!.affiliateId, 'A6000220');
    expect(c.event!.city, 'Cambridge');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // One Swiss section with everyone in it.
    await tap(k('new-section'));
    await tap(k('pool-unassigned'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Section name'),
      'Open',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Rounds'), '3');
    await tester.pumpAndSettle();
    await tap(k('create-section'));
    expect(open().players, hasLength(10));
    expect(open().format, Format.swiss);

    // Round 1.
    await tap(find.text('Pairings'));
    await pairNext();
    expect(open().rounds, hasLength(1));
    expect(open().rounds.single.games, hasLength(5));

    // The no-show is forfeited where they sit and withdrawn from the board.
    final ghost = named('Ghost, Noshow');
    final ghostGame = open().rounds.single.games.firstWhere(
      (g) => g.white == ghost.id || g.black == ghost.id,
    );
    await tap(
      k('score-${ghostGame.id}-${ghostGame.white == ghost.id ? 'w' : 'b'}'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(
      c.event!.games.firstWhere((g) => g.id == ghostGame.id).outcome,
      ghostGame.white == ghost.id ? Outcome.blackForfeit : Outcome.whiteForfeit,
    );
    await tap(k('withdraw-${ghostGame.id}-${ghost.id}'));
    expect(named('Ghost, Noshow').withdrawn, isTrue);

    // A walk-up while round 1 is still being played: in the section at once,
    // with a half-point bye for the round missed.
    await tap(find.text('Players'));
    await tap(find.textContaining('Add player'));
    expect(k('panel-late-entry'), findsOneWidget);
    await tester.enterText(k('panel-name'), 'Late, Larry');
    await tester.enterText(k('panel-memberId'), '12345699');
    await tester.enterText(k('panel-rating'), '1420');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final larry = named('Late, Larry');
    expect(open().players, contains(larry.id));
    expect(c.event!.transitions, isEmpty);
    expect(points('Late, Larry'), 1);
    expect(
      open().rounds.single.byes
          .where((b) => b.player == larry.id)
          .single
          .points,
      1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The rest of round 1 by keyboard, with one draw.
    await tap(find.text('Pairings'));
    final drawn = open().rounds.single.games.firstWhere(
      (g) => g.outcome == Outcome.unreported,
    );
    await type(drawn, LogicalKeyboardKey.keyD);
    expect(
      c.event!.games.firstWhere((g) => g.id == drawn.id).outcome,
      Outcome.draw,
    );
    await finishRound();

    // Typing over a result changes it and says so, with Undo.
    final revision = c.event!.revision;
    await type(drawn, LogicalKeyboardKey.digit1);
    expect(
      c.event!.games.firstWhere((g) => g.id == drawn.id).outcome,
      Outcome.whiteWin,
    );
    expect(find.textContaining('was ½–½'), findsOneWidget);
    await tap(find.widgetWithText(SnackBarAction, 'Undo'));
    expect(
      c.event!.games.firstWhere((g) => g.id == drawn.id).outcome,
      Outcome.draw,
    );
    expect(c.event!.revision, greaterThan(revision));

    // Rounds 2 and 3: ten players still in, so five boards and no bye. The
    // late entry sits at one of them, the no-show at none, and nobody meets
    // the same opponent twice.
    for (final number in [2, 3]) {
      await pairNext();
      expect(open().rounds, hasLength(number));
      final round = open().rounds.last;
      expect(round.games, hasLength(5));
      expect(round.byes.where((b) => b.points > 0), isEmpty);
      final seated = [
        for (final g in round.games) ...[g.white, g.black],
      ];
      expect(seated.toSet(), hasLength(10), reason: 'a player paired twice');
      expect(seated, isNot(contains(ghost.id)));
      expect(seated, contains(larry.id));
      await finishRound();
    }
    final met = <String>{};
    for (final round in open().rounds) {
      for (final g in round.games) {
        final pair = ([g.white, g.black]..sort()).join('|');
        expect(
          met.add(pair),
          isTrue,
          reason: 'repeat pairing in ${round.number}',
        );
      }
    }
    // Fifteen decided games at two half-points each, plus Larry's half-point
    // bye: nothing lost, nothing counted twice. The no-show scored nothing
    // and Larry has exactly the bye on top of his two games.
    final table = standings(c.event!, open());
    expect(table, hasLength(11));
    expect(table.fold<int>(0, (n, r) => n + r.points), 15 * 2 + 1);
    expect(points('Ghost, Noshow'), 0);
    int fromGames(String id) => [
      for (final g in open().rounds.expand((r) => r.games))
        if (g.white == id)
          g.outcome.whiteScore
        else if (g.black == id)
          g.outcome.blackScore,
    ].fold(0, (a, b) => a + b);
    expect(points('Late, Larry'), fromGames(larry.id) + 1);

    // The Export page has nothing left to fix: the no-show without an ID
    // played no game, so the report leaves them out.
    await tap(find.text('Export'));
    expect(k('rating-report'), findsOneWidget);
    expect(k('rating-ready'), findsOneWidget);
    expect(find.text('Ready to generate · 1 section'), findsOneWidget);
    expect(k('rating-blocked'), findsNothing);
    expect(
      tester.widget<ButtonStyleButton>(k('generate-dbf')).onPressed,
      isNotNull,
    );
    expect(ratingPreflight(c.event!), isEmpty);

    // Close the event and open its file again, as after a restart.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
    c = TournamentController(SqliteEventRepository(path));
    final e = c.event!;
    expect(e.sections.single.rounds, hasLength(3));

    // The three files US Chess asks for, decoded.
    final files = ratingPackage(e);
    final header = readDbf(files['THEXPORT.DBF']!).$2.single;
    expect(header['H_AFF_ID'], 'A6000220');
    expect(header['H_CITY'], 'Cambridge');
    expect(header['H_TOT_SECT'], '1');
    final section = readDbf(files['TSEXPORT.DBF']!).$2.single;
    expect(section['S_TIMECTL'], 'G/60;d5');
    expect(section['S_R_SYSTEM'], 'D');
    expect(section['S_TOT_RNDS'], '3');
    final details = readDbf(files['TDEXPORT.DBF']!).$2;
    final names = [for (final row in details) row['D_NAME']];
    expect(names, hasLength(10));
    expect(names, isNot(contains('GHOST, NOSHOW')));
    expect(names, contains('LATE, LARRY'));
    expect(names, contains("O'BRIEN-SMITH JR., SEAN"));
    final late = details.firstWhere((r) => r['D_NAME'] == 'LATE, LARRY');
    expect(late['D_RND01'], startsWith('H'));
    expect(late['D_MEM_ID'], '12345699');
    // Pairing numbers run 1..10 and every opponent reference is one of them.
    expect(
      [for (final row in details) int.parse(row['D_PAIR_NUM']!)],
      [for (var i = 1; i <= 10; i++) i],
    );
    for (final row in details) {
      for (final field in ['D_RND01', 'D_RND02', 'D_RND03']) {
        final match = RegExp(r'^[WLD]\s*(\d+)').firstMatch(row[field]!);
        if (match != null) {
          expect(int.parse(match.group(1)!), inInclusiveRange(1, 10));
        }
      }
    }
  });
}
