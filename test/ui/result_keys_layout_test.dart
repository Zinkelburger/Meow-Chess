// Result keys on keyboards that do not type Latin letters, and the hint
// for the keys a director reaches for to enter a draw as "0.5" or "=".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/result_keys.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

/// A key press as a layout reports it: [character] typed by the key at
/// [physical], whose logical key is that character unless [logical] is
/// given.
KeyDownEvent typed(
  String character,
  PhysicalKeyboardKey physical, {
  LogicalKeyboardKey? logical,
}) => KeyDownEvent(
  physicalKey: physical,
  logicalKey: logical ?? LogicalKeyboardKey(character.runes.first),
  character: character,
  timeStamp: Duration.zero,
);

Future<void> mount(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String legend(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('result-key-legend'))).data!;

void main() {
  test('a Cyrillic or Greek layout scores by key position', () {
    Outcome? white(KeyEvent e, [Outcome current = Outcome.unreported]) =>
        resultFromKey(e, white: true, current: current);
    // Russian: ц d в а з on the W, L, D, F, P keys.
    expect(white(typed('ц', PhysicalKeyboardKey.keyW)), Outcome.whiteWin);
    expect(white(typed('д', PhysicalKeyboardKey.keyL)), Outcome.blackWin);
    expect(white(typed('в', PhysicalKeyboardKey.keyD)), Outcome.draw);
    expect(white(typed('а', PhysicalKeyboardKey.keyF)), Outcome.blackForfeit);
    expect(white(typed('з', PhysicalKeyboardKey.keyP)), Outcome.unfinished);
    // Greek: ς on W, δ on D.
    expect(white(typed('ς', PhysicalKeyboardKey.keyW)), Outcome.whiteWin);
    expect(white(typed('δ', PhysicalKeyboardKey.keyD)), Outcome.draw);
    // Arabic-Indic digits on the number row.
    expect(white(typed('١', PhysicalKeyboardKey.digit1)), Outcome.whiteWin);
    expect(white(typed('٠', PhysicalKeyboardKey.digit0)), Outcome.blackWin);
    // A letter of that layout on any other key is still not a result.
    expect(white(typed('й', PhysicalKeyboardKey.keyQ)), isNull);
    // A forfeit board refuses the draw key there too.
    expect(
      refusedOnForfeit(
        typed('в', PhysicalKeyboardKey.keyD),
        Outcome.whiteForfeit,
      ),
      isTrue,
    );
  });

  test('a Latin layout is taken at its word: the logical key wins', () {
    Outcome? white(KeyEvent e) => resultFromKey(e, white: true);
    // AZERTY: W is typed on the US Z key, and the US W key types Z.
    expect(
      white(
        typed('w', PhysicalKeyboardKey.keyZ, logical: LogicalKeyboardKey.keyW),
      ),
      Outcome.whiteWin,
    );
    expect(
      white(
        typed('z', PhysicalKeyboardKey.keyW, logical: LogicalKeyboardKey.keyZ),
      ),
      isNull,
    );
    // Dvorak types a comma on the US W key, and L on the US P key.
    expect(white(typed(',', PhysicalKeyboardKey.keyW)), isNull);
    expect(
      white(
        typed('l', PhysicalKeyboardKey.keyP, logical: LogicalKeyboardKey.keyL),
      ),
      Outcome.blackWin,
    );
    // AZERTY types & and à on the unshifted 1 and 0 keys: not results.
    expect(white(typed('&', PhysicalKeyboardKey.digit1)), isNull);
    expect(white(typed('à', PhysicalKeyboardKey.digit0)), isNull);
    // Disputed is the character, wherever the layout keeps it.
    expect(white(typed('?', PhysicalKeyboardKey.digit7)), Outcome.disputed);
  });

  test('5, = and the decimal point are draw attempts, with or without a '
      'character', () {
    expect(isDrawAttempt(typed('5', PhysicalKeyboardKey.digit5)), isTrue);
    expect(isDrawAttempt(typed('=', PhysicalKeyboardKey.equal)), isTrue);
    expect(isDrawAttempt(typed('.', PhysicalKeyboardKey.period)), isTrue);
    expect(
      isDrawAttempt(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.numpadDecimal,
          logicalKey: LogicalKeyboardKey.numpadDecimal,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    expect(isDrawAttempt(typed('x', PhysicalKeyboardKey.keyX)), isFalse);
    expect(isDrawAttempt(typed('+', PhysicalKeyboardKey.equal)), isFalse);
  });

  testWidgets('the grid enters a result typed on a Cyrillic layout', (
    tester,
  ) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c);
    final state = tester.state<ResultsViewState>(find.byType(ResultsView));
    final row = state.visibleRows().first;
    await tester.tap(find.byKey(ValueKey('score-${row.game.id}-b')));
    await tester.pump();
    expect(
      state.onKey(row, false, typed('ц', PhysicalKeyboardKey.keyW)),
      KeyEventResult.handled,
    );
    await tester.pump();
    expect(
      c.event!.games.firstWhere((g) => g.id == row.game.id).outcome,
      Outcome.blackWin,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('5, = and the numpad decimal lead the legend with the draw key '
      'and save nothing', (tester) async {
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c);
    final g = c.event!.games.first;
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    final before = c.event!.encode();
    for (final key in [
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.period,
      LogicalKeyboardKey.numpadDecimal,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(legend(tester), startsWith('Draw is D'), reason: '$key');
      expect(c.event!.encode(), before, reason: '$key');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'score ${g.id} white',
        reason: '$key',
      );
      // Announced like any other key that is not a result.
      final semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('result-key-legend')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.liveRegion, isTrue);
      // Another key that is not a result takes the hint away again.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump();
      expect(legend(tester), startsWith('Not a result key'));
      expect(legend(tester), contains('Delete or Backspace clears'));
    }
    // D is the draw key.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(c.event!.games.first.outcome, Outcome.draw);
    await tester.pumpWidget(const SizedBox());
  });
}
