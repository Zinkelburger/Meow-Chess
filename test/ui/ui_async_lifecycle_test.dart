import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/ui/dialogs.dart';
import 'package:meow_chess/ui/panels.dart';

import '../support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a save that finishes after its panel closed clears the draft', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final saving = Completer<void>();
    Map<String, String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FieldsPanel(
            title: 'Team',
            fields: const [FieldSpec('team', 'Team')],
            values: const {'team': 'Rooks'},
            controller: c,
            draftKey: 'draft:test-team',
            onSave: (values) {
              saved = values;
              return saving.future;
            },
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Knights');
    expect(c.workspaceState.read('draft:test-team'), isNotEmpty);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved, {'team': 'Knights'});

    // The panel closes (say, the TD switched sections) while saving.
    await tester.pumpWidget(const SizedBox());
    saving.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(c.workspaceState.read('draft:test-team') ?? '', isEmpty);
  });

  testWidgets('a failed Open event picker is shown, not dropped', (
    tester,
  ) async {
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    final directory = Directory.systemTemp.createTempSync('meow-open-fail-');
    final diagnostics = <String>[];
    final previousSink = Diagnostics.sink;
    Diagnostics.sink = diagnostics.add;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      picker,
      (_) async =>
          throw PlatformException(code: 'portal', message: 'No portal'),
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null);
      Diagnostics.sink = previousSink;
      directory.deleteSync(recursive: true);
    });

    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open event'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Copy error message'), findsOneWidget);
    expect(find.textContaining('Could not choose an event.'), findsOneWidget);
    expect(diagnostics.join('\n'), contains('choose event file — failed'));
    await tester.pumpWidget(const SizedBox());
  });
}
