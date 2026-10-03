import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/ui/workspace_actions.dart';

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
    destination = '${directory.path}/existing.meow';
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

  testWidgets('failed replacement logs destination, error and stack', (
    tester,
  ) async {
    final active = SqliteEventRepository(destination);
    addTearDown(active.close);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => destination,
    );
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
    expect(log, contains('path: $destination'));
    expect(log, contains('This event may be open or awaiting recovery.'));
    expect(log, contains('Stack trace:'));
    expect(log, isNot(contains('create event file — succeeded')));
    expect(find.byTooltip('Copy error message'), findsOneWidget);
    expect(active.load()!.name, 'Previous tournament');
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final accept in [true, false]) {
    testWidgets(
      'new tournament honors native save ${accept ? 'Replace' : 'Cancel'}',
      (tester) async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          expect(call.method, 'save');
          expect(call.arguments, 'new-tournament.meow');
          return accept ? destination : null;
        });
        await tester.pumpWidget(MeowApp(dataDirectory: directory));
        await tester.pumpAndSettle();
        await tester.tap(find.text('New tournament'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('new-event-name')),
          'New tournament',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          find.text('That file already exists. Pick a new name.'),
          findsNothing,
        );
        if (!accept) {
          expect(File(destination).readAsBytesSync(), original);
          expect(find.byKey(const ValueKey('new-event-name')), findsOneWidget);
          expect(directory.listSync().map((file) => file.path), [destination]);
          expect(diagnostics.join('\n'), contains('save dialog — cancelled'));
          expect(diagnostics.join('\n'), isNot(contains('Create event')));
        } else {
          expect(diagnostics.join('\n'), contains('path: $destination'));
        }
        await tester.pumpWidget(const SizedBox());
        final reopened = SqliteEventRepository(destination);
        expect(
          reopened.load()!.name,
          accept ? 'New tournament' : 'Previous tournament',
        );
        expect(reopened.history(), hasLength(1));
        reopened.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

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
