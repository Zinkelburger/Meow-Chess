import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/main.dart';
import 'package:path/path.dart' as p;

import '../support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const open = MethodChannel('meow_chess/file_open');
  const save = MethodChannel('meow_chess/file_save');
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-template-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(open, (call) async {
      if (call.method == 'ready') return <String>[];
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(open, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(save, null);
    directory.deleteSync(recursive: true);
  });

  testWidgets('New event like… copies a recent event\'s set-up only', (
    tester,
  ) async {
    final source = p.join(directory.path, 'friday-blitz.meow');
    final c = fixture(count: 8, format: Format.swiss, path: source);
    c.change(
      'Announce',
      c.event!.copy(name: 'Friday Blitz', timeControl: 'G/5 d0'),
    );
    c.dispose();
    File(
      p.join(directory.path, 'library.json'),
    ).writeAsStringSync(jsonEncode([source]));
    final destination = p.join(directory.path, 'next.meow');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      save,
      (_) async => destination,
    );
    // A laptop window (the brief's fidelity target). At the 800x600 test
    // default the welcome header pushes the one-line copy note just below
    // the fold of the lazily built list, so it was never found on screen.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-event-like')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.text(
        'Copied from Friday Blitz: 2 sections, time control. '
        'No players, results or rulings.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Friday Blitz 2',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // The new event is now open in the workspace, which holds the file's
    // lock; close the app before reading it back.
    await tester.pumpWidget(const SizedBox());
    final repository = SqliteEventRepository(destination);
    addTearDown(repository.close);
    final made = repository.load()!;
    expect(made.name, 'Friday Blitz 2');
    expect(made.timeControl, 'G/5 d0');
    expect(made.players, isEmpty);
    expect(made.sections.map((s) => s.name), ['Quad 1', 'Quad 2']);
    expect(made.sections.every((s) => s.players.isEmpty), isTrue);
    expect(made.sections.every((s) => s.format == Format.swiss), isTrue);
    // The mocked meow_chess/file_save channel is the Linux save dialog;
    // under the test default (Android) the file_selector path ran instead
    // and nothing was saved.
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
