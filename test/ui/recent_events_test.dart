import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/file_open');
  late Directory directory;
  late File event;
  late File library;
  late List<MethodCall> reveals;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-recent-');
    event = File('${directory.path}/Saturday café #1.meow')
      ..writeAsStringSync('unchanged');
    library = File('${directory.path}/library.json')
      ..writeAsStringSync(jsonEncode([event.path]));
    reveals = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'ready') return <String>[];
      reveals.add(call);
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  testWidgets('folder button reveals the event and leaves the list intact', (
    tester,
  ) async {
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    final reveal = find.byTooltip('View in file explorer');
    final remove = find.byTooltip('Remove from recent events');
    await tester.ensureVisible(reveal);
    await tester.pumpAndSettle();
    expect(tester.getCenter(reveal).dx, lessThan(tester.getCenter(remove).dx));

    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(reveals.single.method, 'reveal');
    expect(reveals.single.arguments, event.absolute.path);
    expect(find.text('Recent events'), findsOneWidget);
    expect(find.textContaining('Could not open this event'), findsNothing);
    expect(jsonDecode(library.readAsStringSync()), [event.path]);
    expect(event.readAsStringSync(), 'unchanged');

    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('Recent events'), findsNothing);
    expect(jsonDecode(library.readAsStringSync()), isEmpty);
    expect(event.existsSync(), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing an event drops every spelling of its path', (
    tester,
  ) async {
    final alias = '${directory.path}/./${event.path.split('/').last}';
    library.writeAsStringSync(jsonEncode([event.path, alias]));
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();

    final remove = find.byTooltip('Remove from recent events').first;
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('Recent events'), findsNothing);
    expect(jsonDecode(library.readAsStringSync()), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('file explorer failures are shown without removing the event', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'ready') return <String>[];
      throw PlatformException(code: 'reveal_failed', message: 'File not found');
    });
    await tester.pumpWidget(MeowApp(dataDirectory: directory));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('View in file explorer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View in file explorer'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not show this file in the file explorer.'),
      findsOneWidget,
    );
    expect(find.text('Recent events'), findsOneWidget);
    expect(jsonDecode(library.readAsStringSync()), [event.path]);
    await tester.pumpWidget(const SizedBox());
  });
}
