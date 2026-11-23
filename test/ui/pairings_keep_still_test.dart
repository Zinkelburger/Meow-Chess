// Nothing on the Pairings page moves while round after round is paired and
// its results are typed: no control, heading or table jumps under the
// director's eye or pointer.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

import 'workspace_host.dart';

/// Where every keyed widget on screen is, by key.
Map<String, Rect> layout(WidgetTester tester) {
  final out = <String, Rect>{};
  void visit(Element e) {
    if (e.widget.key case final ValueKey<Object?> key
        when e.renderObject is RenderBox) {
      final box = e.renderObject! as RenderBox;
      if (box.attached && box.hasSize) {
        out.putIfAbsent(
          '${key.value}',
          () => box.localToGlobal(Offset.zero) & box.size,
        );
      }
    }
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return out;
}

/// Rows that are meant to move: crosstable rows re-sort by score, and a
/// result changes its own board's marks. "Enter 2 results first" is
/// right-aligned text that is meant to change.
bool moves(String key) =>
    key.startsWith('(player-row') ||
    key == 'post-blocked' ||
    RegExp(
      r'^(number|player|rank|round|standing-score|game|score|bye|bye-player)-',
    ).hasMatch(key);

/// The keyed widgets that moved or changed size between [before] and
/// [after], other than those meant to.
List<String> shifted(Map<String, Rect> before, Map<String, Rect> after) => [
  for (final MapEntry(:key, value: now) in after.entries)
    if (before[key] case final was? when !moves(key))
      if ((now.topLeft - was.topLeft).distance > .5 ||
          ((now.size - was.size) as Offset).distance > .5)
        '$key: $was -> $now',
];

TournamentController swiss(int n) {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < n; i++)
      Player(
        id: 'p$i',
        name: 'Player ${i.toString().padLeft(2, '0')}',
        rating: 2000 - i * 37,
        memberId: '${12000000 + i}',
      ),
  ]);
  c.addSection('Open', Format.swiss, 4);
  return c;
}

void main() {
  for (final size in [const Size(1400, 900), const Size(1000, 800)]) {
    testWidgets('a ${size.width.toInt()}-wide window keeps still while '
        'rounds are paired and results typed', (tester) async {
      final c = swiss(13);
      addTearDown(c.dispose);
      await mountWorkspace(tester, c, size: size);
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      await pickTab(tester, c.event!.sections.single.id);

      for (var round = 1; round <= 3; round++) {
        // Pressing Create pairings: the button keeps its size while it works.
        final ready = layout(tester);
        final before = c.event!.revision;
        await tester.tap(find.byKey(const ValueKey('pair-next-round')));
        await tester.pump();
        expect(
          shifted(ready, layout(tester)),
          isEmpty,
          reason: 'round $round, pairing',
        );
        await tester.runAsync(() async {
          for (var i = 0; i < 300 && c.event!.revision == before; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(c.event!.sections.single.rounds, hasLength(round));
        if (round == 3) break;

        // Typing every result from the keyboard: nothing moves but the
        // board's own marks and the crosstable's order.
        final games = c.event!.sections.single.rounds.last.games;
        await tester.tap(find.byKey(ValueKey('score-${games.first.id}-w')));
        await tester.pumpAndSettle();
        for (var i = 0; i < games.length; i++) {
          final typing = layout(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
          await tester.pumpAndSettle();
          final now = layout(tester);
          expect(
            shifted(typing, now),
            isEmpty,
            reason: 'round $round, result ${i + 1}',
          );
        }
        expect(
          c.event!.sections.single.rounds.last.games.every(
            (g) => g.outcome.resolved,
          ),
          isTrue,
        );
      }
    });
  }
}
