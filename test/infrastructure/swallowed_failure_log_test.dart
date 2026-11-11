import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/application/workspace_state.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

/// A failure the app recovers from still has to leave a trace in the log.
void main() {
  late List<String> log;
  void Function(String)? previous;

  setUp(() {
    log = [];
    previous = Diagnostics.sink;
    Diagnostics.sink = log.add;
  });
  tearDown(() => Diagnostics.sink = previous);

  group('US Chess responses', () {
    const secret = 'Private Member Response';
    RatingsApi api(String body) => RatingsApi(
      MockClient((request) async => http.Response(body, 200)),
    );

    test('an unreadable search is logged without the response', () async {
      await expectLater(
        api('{"$secret": ').search('Test Member'),
        throwsA(isA<TournamentException>()),
      );
      expect(log, hasLength(1));
      expect(log.single, contains('search members'));
      expect(log.single, contains('FormatException'));
      expect(log.single, isNot(contains(secret)));
    });

    test('a known lookup failure is not reported as unreadable', () async {
      final client = RatingsApi(
        MockClient((request) async => http.Response('', 429)),
      );
      await expectLater(
        client.search('Test Member'),
        throwsA(isA<MemberLookupFailure>()),
      );
      expect(log, isEmpty);
    });

    test('a member search result that is valid logs nothing', () async {
      final results = await api(
        jsonEncode({'items': <Object?>[]}),
      ).search('Test Member');
      expect(results, isEmpty);
      expect(log, isEmpty);
    });
  });

  group('paper size', () {
    late Directory dir;
    late PrinterPreference preference;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('meow-paper-log');
      preference = PrinterPreference(directory: dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('never having chosen one is normal and logs nothing', () async {
      expect(await preference.readA4(), false);
      expect(log, isEmpty);
    });

    test('a damaged file falls back to Letter and is logged', () async {
      File('${dir.path}/paper.json').writeAsStringSync('{not json');
      expect(await preference.readA4(), false);
      expect(log, hasLength(1));
      expect(log.single, contains('read paper size'));
    });
  });

  test('a damaged draft starts empty and is logged once', () {
    final repository = SqliteEventRepository(':memory:');
    final store = WorkspaceState(repository);
    addTearDown(store.dispose);
    addTearDown(repository.close);
    repository.writePreference('draft', '{not json');
    expect(store.readMap('draft'), isEmpty);
    expect(store.readMap('draft'), isEmpty);
    expect(log, hasLength(1));
    expect(log.single, contains('read saved draft'));
    expect(log.single, contains('key: draft'));
  });
}
