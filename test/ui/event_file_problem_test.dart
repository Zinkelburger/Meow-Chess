import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/main.dart';
import 'package:path/path.dart' as p;

import '../support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const save = MethodChannel('meow_chess/file_save');
  late Directory directory;
  late String eventPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-file-problem-');
    eventPath = p.join(directory.path, 'event.meow');
    fixture(path: eventPath).dispose();
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(save, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> start(WidgetTester tester, {String? open}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, initialPath: open),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a deleted event file stops "Event saved" and a copy carries on',
    (tester) async {
      await start(tester, open: eventPath);
      expect(find.byKey(const ValueKey('event-file-problem')), findsNothing);
      expect(find.textContaining('Event saved'), findsOneWidget);
      File(eventPath).deleteSync();
      // Noticed by the periodic look, with nothing entered meanwhile.
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      expect(find.byKey(const ValueKey('event-file-problem')), findsOneWidget);
      expect(find.textContaining('Event saved'), findsNothing);
      expect(find.text('Event file moved or deleted'), findsOneWidget);
      // Told inline: nothing opens over the workspace.
      expect(find.byType(Dialog), findsNothing);
      final copy = p.join(directory.path, 'carry-on.meow');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        save,
        (_) async => copy,
      );
      await tester.tap(find.text('Save a copy…'));
      await tester.pumpAndSettle();
      // Now working in the copy, which is a file again.
      expect(File(copy).existsSync(), isTrue);
      expect(find.byKey(const ValueKey('event-file-problem')), findsNothing);
      expect(find.textContaining('Event saved'), findsOneWidget);
      expect(find.textContaining('carry-on.meow'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    skip: Platform.isWindows,
  );

  testWidgets('New event like… only reads the event it copies from', (
    tester,
  ) async {
    final gone = p.join(directory.path, 'gone.meow');
    File(
      p.join(directory.path, 'library.json'),
    ).writeAsStringSync(jsonEncode([gone, eventPath]));
    final bytes = File(eventPath).readAsBytesSync();
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('new-event-like')));
    await tester.pumpAndSettle();
    // The first recent event is missing: nothing is made in its place.
    expect(find.text('That event could not be read.'), findsOneWidget);
    expect(File(gone).existsSync(), isFalse);
    await chooseOption(
      tester,
      find.byKey(const ValueKey('new-event-template')),
      'event',
    );
    expect(find.textContaining('Copies from Saturday Quads'), findsOneWidget);
    // Redrawing does not read it again, and reading never changed it.
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Next week',
    );
    await tester.pumpAndSettle();
    expect(File(eventPath).readAsBytesSync(), bytes);
    expect(
      directory.listSync().map((f) => p.basename(f.path)).toSet(),
      {'event.meow', 'library.json', 'logs'}.intersection(
        directory.listSync().map((f) => p.basename(f.path)).toSet(),
      ),
    );
    expect(File('$eventPath-wal').existsSync(), isFalse);
    expect(File('$eventPath-shm').existsSync(), isFalse);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
