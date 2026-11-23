import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/event_folder.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/ui/workspace_actions.dart';

import '../support.dart';

void main() {
  const channel = MethodChannel('meow_chess/file_save');
  late Directory directory;
  late String destination;
  late List<int> original;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> diagnostics;
  void Function(String)? previousSink;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-save-dialog-');
    destination = p.join(directory.path, 'existing.meow');
    final c = TournamentController(SqliteEventRepository(destination));
    c.create('Previous tournament');
    c.dispose();
    original = File(destination).readAsBytesSync();
    diagnostics = [];
    previousSink = Diagnostics.sink;
    Diagnostics.sink = diagnostics.add;
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    Diagnostics.sink = previousSink;
    directory.deleteSync(recursive: true);
  });

  testWidgets('a new tournament gets a folder of its own', (tester) async {
    final parent = Directory(p.join(directory.path, 'Tournaments'))
      ..createSync();
    File(
      p.join(directory.path, 'settings.json'),
    ).writeAsStringSync(jsonEncode({'tournamentsFolder': parent.path}));
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tournament'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Tornado #150',
    );
    await tester.pump();
    final folder = p.join(parent.path, 'Tornado #150');
    expect(find.text('Saved in $folder'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(diagnostics.join('\n'), contains('create event file — succeeded'));
    await tester.pumpWidget(const SizedBox());
    final made = p.join(folder, 'tornado-150.meow');
    final reopened = SqliteEventRepository(made);
    expect(reopened.load()!.name, 'Tornado #150');
    expect(reopened.history(), hasLength(1));
    reopened.close();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('an open event keeps SwissSys files in its own folder', (
    tester,
  ) async {
    final folder = Directory(p.join(directory.path, 'Saturday Quads'))
      ..createSync();
    final path = p.join(folder.path, 'saturday-quads.meow');
    final c = fixture(count: 8, path: path);
    // As New tournament records the folder it made for the event.
    markEventFolder(c.repository, folder.path);
    c.dispose();
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, initialPath: path),
    );
    await tester.pumpAndSettle();
    List<String> swissSys() => [
      for (final f in folder.listSync())
        if (p.basename(f.path).contains('.S')) p.basename(f.path),
    ]..sort();
    expect(swissSys(), ['Quad 1.S0C', 'Quad 2.S0C']);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('an older event kept alone in a folder gets nothing written', (
    tester,
  ) async {
    // As an event saved on its own to the Desktop by an earlier version.
    final desktop = Directory(p.join(directory.path, 'Desktop'))..createSync();
    final path = p.join(desktop.path, 'club.meow');
    fixture(count: 8, path: path).dispose();
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, initialPath: path),
    );
    await tester.pumpAndSettle();
    expect([
      for (final f in desktop.listSync())
        if (!p.basename(f.path).startsWith('club.meow')) p.basename(f.path),
    ], isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a folder already in use is refused, and nothing replaced', (
    tester,
  ) async {
    File(
      p.join(directory.path, 'settings.json'),
    ).writeAsStringSync(jsonEncode({'tournamentsFolder': directory.path}));
    final used = Directory(p.join(directory.path, 'Replacement'))..createSync();
    final kept = File(p.join(used.path, 'notes.txt'))..writeAsStringSync('x');
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tournament'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Replacement',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final log = diagnostics.join('\n');
    expect(log, contains('ERROR create event file — failed'));
    expect(log, contains('Replacement already exists in'));
    expect(log, isNot(contains('create event file — succeeded')));
    expect(find.byTooltip('Copy error message'), findsOneWidget);
    expect(used.listSync().map((f) => f.path), [kept.path]);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the first event goes in Documents/Meow-Chess without asking', (
    tester,
  ) async {
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    var asked = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
      call,
    ) async {
      asked++;
      return null;
    });
    addTearDown(
      () =>
          binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null),
    );
    // Not made yet, as on a first launch.
    final standard = p.join(directory.path, 'Documents', 'Meow-Chess');
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, defaultTournamentsFolder: standard),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tournament'));
    await tester.pumpAndSettle();
    expect(find.text('Saved in a new folder in $standard'), findsOneWidget);
    expect(find.text('Change…'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Club Night',
    );
    await tester.pump();
    expect(
      find.text('Saved in ${p.join(standard, 'Club Night')}'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(asked, 0);
    await tester.pumpWidget(const SizedBox());
    expect(
      File(p.join(standard, 'Club Night', 'club-night.meow')).existsSync(),
      isTrue,
    );
    // Nothing was chosen, so nothing is remembered as a choice.
    expect(File(p.join(directory.path, 'settings.json')).existsSync(), false);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Change… moves new events to the folder picked', (tester) async {
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    final elsewhere = Directory(p.join(directory.path, 'USB'))..createSync();
    Object? startedIn;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
      call,
    ) async {
      startedIn = call.arguments;
      return elsewhere.path;
    });
    addTearDown(
      () =>
          binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null),
    );
    final standard = p.join(directory.path, 'Documents', 'Meow-Chess');
    // A laptop window: at the 800x600 test default the folder line is below
    // the fold of the welcome screen.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, defaultTournamentsFolder: standard),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tournament'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-tournaments-folder')));
    await tester.pumpAndSettle();
    // The window opens on the nearest folder that exists.
    expect('$startedIn', contains(directory.path));
    expect('$startedIn', isNot(contains('Meow-Chess')));
    expect(
      find.text('Saved in a new folder in ${elsewhere.path}'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Club Night',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(
      File(
        p.join(elsewhere.path, 'Club Night', 'club-night.meow'),
      ).existsSync(),
      isTrue,
    );
    expect(Directory(standard).existsSync(), false);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('with no Documents folder, the first event asks once', (
    tester,
  ) async {
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    String? answer;
    var asked = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
      call,
    ) async {
      expect(call.method, 'getDirectoryPath');
      asked++;
      return answer;
    });
    addTearDown(
      () =>
          binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null),
    );
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tournament'));
    await tester.pumpAndSettle();
    expect(
      find.text('Each event gets a folder of its own. Choose where they go.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Club Night',
    );
    // Cancelling the folder window makes nothing.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.byKey(const ValueKey('new-event-name')), findsOneWidget);
    expect(Directory(p.join(directory.path, 'Club Night')).existsSync(), false);

    answer = directory.path;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(asked, 2);
    await tester.pumpWidget(const SizedBox());
    final made = p.join(directory.path, 'Club Night', 'club-night.meow');
    expect(File(made).existsSync(), isTrue);
    expect(
      File(p.join(directory.path, 'settings.json')).readAsStringSync(),
      contains('tournamentsFolder'),
    );

    // The next event goes beside it without asking.
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tournament'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-event-name')),
      'Club Night 2',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(asked, 2);
    await tester.pumpWidget(const SizedBox());
    expect(
      File(
        p.join(directory.path, 'Club Night 2', 'club-night-2.meow'),
      ).existsSync(),
      isTrue,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final accept in [true, false]) {
    testWidgets(
      'save copy honors native save ${accept ? 'Replace' : 'Cancel'}',
      (tester) async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          expect(call.method, 'save');
          return accept ? destination : null;
        });
        final c = TournamentController(SqliteEventRepository(':memory:'));
        c.create('Current tournament');
        addTearDown(c.dispose);
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold();
              },
            ),
          ),
        );
        await WorkspaceActions(context, c).saveCopy();
        await tester.pumpAndSettle();
        if (!accept) expect(File(destination).readAsBytesSync(), original);
        final reopened = SqliteEventRepository(destination);
        expect(
          reopened.load()!.name,
          accept ? 'Current tournament' : 'Previous tournament',
        );
        reopened.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}
