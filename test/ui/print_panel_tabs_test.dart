import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:meow_chess/ui/side_panel.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';
import 'dock_host.dart';

void main() {
  const labels = ['Standings', 'Crosstable', 'Wall chart', 'Prizes'];

  // The dock's column: 360 wide from the minimum window (960) upward.
  for (final (width, scale) in [
    (detailsColumnWidth(1400), 1.0),
    (detailsColumnWidth(1400), 2.0),
    (detailsColumnWidth(960), 1.0),
    (detailsColumnWidth(960), 2.0),
    // Narrower still, as when the panel is hosted in a smaller column.
    (320.0, 1.0),
  ]) {
    testWidgets('sheet names stay whole at $width wide, ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final pending = Completer<Uint8List>();
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
              child: SizedBox(
                width: width,
                child: PrintPanel(
                  event: c.event!,
                  controller: c,
                  kind: ReportKind.standings,
                  onClose: () {},
                  generate: (_) => pending.future,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byKey(const ValueKey('print-panel')));
      final kinds = find.byKey(const ValueKey('print-ranking-kind'));
      for (final label in labels) {
        final text = find.descendant(of: kinds, matching: find.text(label));
        expect(text, findsOneWidget, reason: label);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        // One line, the whole word: not wrapped, not cut short.
        expect(paragraph.didExceedMaxLines, false, reason: label);
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(
            paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
          ),
          reason: '$label is squeezed',
        );
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(
          paragraph.size.height,
          lessThan(painter.height * 1.5),
          reason: '$label takes two lines',
        );
        painter.dispose();
        final chip = tester.getRect(
          find.ancestor(of: text, matching: find.byType(ChoiceChip)),
        );
        expect(chip.left, greaterThanOrEqualTo(panel.left), reason: label);
        expect(chip.right, lessThanOrEqualTo(panel.right), reason: label);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('choosing a sheet opens that sheet; the chosen one is marked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: DockHost(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => Dock.maybeOf(context)!.show(
                  'print',
                  PrintPanel(
                    event: c.event!,
                    controller: c,
                    kind: ReportKind.standings,
                    onClose: () {},
                    generate: (_) => pending.future,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    ChoiceChip chip(String name) =>
        tester.widget<ChoiceChip>(find.byKey(ValueKey('print-kind-$name')));
    expect(chip('standings').selected, true);
    expect(chip('crosstable').selected, false);
    await tester.tap(find.byKey(const ValueKey('print-kind-crosstable')));
    await tester.pump();
    expect(
      tester.widget<PrintPanel>(find.byType(PrintPanel)).kind,
      ReportKind.crosstable,
    );
    expect(chip('crosstable').selected, true);
    expect(chip('standings').selected, false);
    await tester.pumpWidget(const SizedBox());
  });
}
