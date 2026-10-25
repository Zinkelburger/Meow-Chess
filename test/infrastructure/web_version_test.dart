import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/proxy_client.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:path/path.dart' as p;

import 'rating_contract_test.dart' show exportFixture, today;

/// The pieces the browser version (docs/WEB.md) adds that also run on the VM.
void main() {
  group('ProxyClient', () {
    final endpoint = Uri.parse('https://chessautoprep.com/meow-chess/fetch');

    test('sends other sites through the fetch function', () async {
      late http.Request seen;
      final client = ProxyClient(
        MockClient((request) async {
          seen = request;
          return http.Response('ok', 200);
        }),
        endpoint,
      );
      final request =
          http.Request(
              'GET',
              Uri.https('ratings-api.uschess.org', '/api/v2/members/1', {
                'a': 'b c',
              }),
            )
            ..followRedirects = false
            ..headers.addAll({'Accept': 'application/json', 'X-Api-Key': 'k'});
      final response = await client.send(request);
      expect(await response.stream.bytesToString(), 'ok');
      expect(seen.url.replace(query: '').toString(), '$endpoint?');
      expect(
        seen.url.queryParameters['url'],
        'https://ratings-api.uschess.org/api/v2/members/1?a=b+c',
      );
      expect(seen.headers['Accept'], 'application/json');
      expect(seen.headers['X-Api-Key'], 'k');
      expect(seen.followRedirects, isFalse);
    });

    test('leaves requests to its own site alone', () async {
      late http.Request seen;
      final client = ProxyClient(
        MockClient((request) async {
          seen = request;
          return http.Response('', 204);
        }),
        endpoint,
      );
      await client.get(Uri.parse('https://chessautoprep.com/meow-chess/a'));
      expect(seen.url.toString(), 'https://chessautoprep.com/meow-chess/a');
    });
  });

  test('the rating package zip holds the DBFs and manifest', () {
    final event = exportFixture();
    final files = ratingPackage(event, today: today);
    final zip = ZipDecoder().decodeBytes(
      ratingPackageZip(event, now: () => today),
    );
    expect(
      zip.files.map((f) => f.name).toSet(),
      {...files.keys, 'manifest.json'},
    );
    for (final entry in files.entries) {
      expect(zip.findFile(entry.key)!.content, entry.value);
    }
    final manifest = jsonDecode(
      utf8.decode(zip.findFile('manifest.json')!.content),
    );
    expect(manifest['revision'], event.revision);
  });

  test('history snapshots compressed in the browser open on desktop', () {
    // The browser writes them with package:archive; desktop reads dart:io zlib.
    final state = utf8.encode(exportFixture().encode());
    expect(zlib.decode(const ZLibEncoder().encodeBytes(state)), state);
    expect(const ZLibDecoder().decodeBytes(zlib.encode(state)), state);
  });

  test('snapshotBytes is an independently openable copy', () {
    final directory = Directory.systemTemp.createTempSync('meow-web-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final controller = TournamentController(
      SqliteEventRepository(p.join(directory.path, 'open.meow')),
    );
    addTearDown(controller.dispose);
    controller.change('Load fixture', exportFixture());
    final copy = File(p.join(directory.path, 'copy.meow'))
      ..writeAsBytesSync(controller.repository.snapshotBytes());
    final reopened = SqliteEventRepository(copy.path);
    addTearDown(reopened.close);
    expect(reopened.load()!.encode(), controller.event!.encode());
    expect(reopened.historyGraph().nodes, isNotEmpty);
  });
}
