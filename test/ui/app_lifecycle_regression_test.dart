import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/main.dart';
import 'package:path/path.dart' as p;
import '../support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const files = MethodChannel('meow_chess/file_open');
  late Directory directory;
  late String eventPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-lifecycle-');
    eventPath = p.join(directory.path, 'event.meow');
    fixture(path: eventPath).dispose();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MeowApp(dataDirectory: directory, initialPath: eventPath),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFromDesktop(WidgetTester tester, String filename) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      files.name,
      files.codec.encodeMethodCall(MethodCall('open', [filename])),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  test('event names become plain file names', () {
    expect(fileStem('Torneo Año'), 'torneo-ano');
    expect(fileStem('Saturday Quads'), 'saturday-quads');
    expect(fileStem('  Café Open #3 '), 'cafe-open-3');
    expect(fileStem('!!!'), 'tournament');
  });

  testWidgets('quitting closes the event and its recovery file', (
    tester,
  ) async {
    await start(tester);
    expect(SqliteEventRepository.ownsPath(eventPath), isTrue);
    late ByteData? reply;
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.platform.name,
      SystemChannels.platform.codec.encodeMethodCall(
        const MethodCall('System.requestAppExit'),
      ),
      (data) => reply = data,
    );
    expect(SystemChannels.platform.codec.decodeEnvelope(reply!), {
      'response': 'exit',
    });
    expect(SqliteEventRepository.ownsPath(eventPath), isFalse);
    final wal = File('$eventPath-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the open event asked for again by another name stays open', (
    tester,
  ) async {
    await start(tester);
    await openFromDesktop(tester, p.join(directory.path, '.', 'event.meow'));
    expect(find.textContaining('Could not open this event'), findsNothing);
    expect(find.text('Saturday Quads'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unwritable recent list does not fail the open', (
    tester,
  ) async {
    // A folder where library.json belongs makes every write to it fail.
    Directory(p.join(directory.path, 'library.json')).createSync();
    await start(tester);
    final second = p.join(directory.path, 'second.meow');
    fixture(path: second).dispose();
    await openFromDesktop(tester, second);
    expect(find.textContaining('Could not open this event'), findsNothing);
    expect(SqliteEventRepository.ownsPath(second), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing after a failed desktop open shows a clean welcome', (
    tester,
  ) async {
    await start(tester);
    await openFromDesktop(tester, p.join(directory.path, 'missing.meow'));
    expect(find.textContaining('Could not open this event'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close event'));
    await tester.pumpAndSettle();
    expect(find.text('Recent events'), findsOneWidget);
    expect(find.textContaining('Could not open this event'), findsNothing);
    // The event closes once its views have gone.
    expect(SqliteEventRepository.ownsPath(eventPath), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
