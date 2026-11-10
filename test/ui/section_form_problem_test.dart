import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/new_section_panel.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

const roundsProblem = 'Number of rounds must be between 1 and 32.';

Future<void> mount(WidgetTester tester, Widget panel, double scale) async {
  tester.view.physicalSize = const Size(1200, 2600);
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
      // The dock's column in the workspace.
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 384, child: panel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The whole sentence is on screen: every line laid out, none cut off, and
/// no narrower than the field row it explains.
void expectReadable(
  WidgetTester tester,
  String sentence,
  Finder field,
  double scale,
) {
  final text = find.text(sentence);
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, false);
  expect(tester.takeException(), isNull);
  final panel = tester.getRect(find.byType(Scaffold));
  final rect = tester.getRect(text);
  expect(rect.left, greaterThanOrEqualTo(panel.left));
  // Not squeezed into the narrow Rounds column: at normal text size the
  // sentence has the panel's width, under the Rounds and Time control row.
  final line = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout();
  final lines = (rect.height / line.height).round();
  final unbroken = line.width;
  line.dispose();
  if (scale == 1) {
    expect(rect.width, greaterThan(tester.getSize(field).width * 2));
    expect(rect.top, greaterThanOrEqualTo(tester.getRect(field).bottom));
  }
  // No more lines than the sentence needs at the width it was given.
  expect(lines, lessThanOrEqualTo((unbroken / rect.width).ceil() + 1));
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('section settings show a Rounds problem in full at ${scale}x', (
      tester,
    ) async {
      final c = fixture(count: 4, format: Format.swiss);
      addTearDown(c.dispose);
      final id = c.event!.sections.single.id;
      await mount(tester, sectionSettingsPanel(c, id, () {}), scale);
      final rounds = find.byKey(const ValueKey('field-rounds'));
      await tester.enterText(rounds, '99');
      await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
      await tester.tap(find.byKey(const ValueKey('save-section')));
      await tester.pumpAndSettle();
      expectReadable(tester, roundsProblem, rounds, scale);
      expect(c.event!.sections.single.plannedRounds, isNot(99));

      // Time control, the other half of the row, reads in full too.
      await tester.enterText(rounds, '3');
      await tester.enterText(
        find.byKey(const ValueKey('field-timeControl')),
        'fast',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-section')));
      await tester.tap(find.byKey(const ValueKey('save-section')));
      await tester.pumpAndSettle();
      expect(find.text(roundsProblem), findsNothing);
      final problem = find.byKey(const ValueKey('field-timeControl-problem'));
      if (scale == 1) {
        expect(problem, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(problem);
        expect(paragraph.didExceedMaxLines, false);
        expect(
          tester.getSize(problem).width,
          greaterThan(tester.getSize(rounds).width * 2),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('New section shows a Rounds problem in full at ${scale}x', (
      tester,
    ) async {
      final c = fixture(count: 4, format: Format.swiss);
      addTearDown(c.dispose);
      await mount(
        tester,
        NewSectionPanel(
          controller: c,
          ticked: const {},
          onCreated: (_) {},
          onClose: () {},
        ),
        scale,
      );
      await tester.tap(find.text('Swiss'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-section-name')),
        'Extra',
      );
      final rounds = find.byKey(const ValueKey('new-section-rounds'));
      await tester.enterText(rounds, '99');
      await tester.pumpAndSettle();
      final create = find.byKey(const ValueKey('create-section'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expectReadable(tester, roundsProblem, rounds, scale);
      expect(c.event!.sections, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
