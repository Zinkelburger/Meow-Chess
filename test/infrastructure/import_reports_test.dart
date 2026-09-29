import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import '../support.dart';

void main() {
  test(
    'quoted CSV, BOM, leading-zero IDs and rejected rows preserve originals',
    () {
      final rows = parseRoster(
        '\uFEFFName,US Chess ID,Rating\r\n"Lee, Morgan",00123456,1600\r\nBad,abc,1500\r\n"Multi\nLine",12345678,0',
      );
      expect(rows.length, 3);
      expect(rows.first.player!.name, 'Lee, Morgan');
      expect(rows.first.player!.memberId, '00123456');
      expect(rows[1].error, isNotNull);
      expect(rows.last.player!.name, 'Multi\nLine');
    },
  );
  test(
    'tab-delimited spreadsheet paste and reimport do not erase corrections',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final rows = parseRoster('Name\tID\tRating\nNew Player\t00123456\t1550');
      c.importPlayers(rows.map((r) => r.player!).toList());
      expect(c.event!.players.length, 5);
      c.savePlayer(
        c.event!.players.last.copy(name: 'Corrected Name', rating: 1600),
      );
      expect(
        () => c.importPlayers(rows.map((r) => r.player!).toList()),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.players.last.name, 'Corrected Name');
    },
  );
  test(
    'reports do not leak private notes, IDs, API data or input provenance',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(notes: 'private medical note'));
      c.post(await c.propose());
      final text = crosstable(c.event!);
      expect(text, contains('Quad 1'));
      expect(text, isNot(contains('private')));
      expect(text, isNot(contains('12000000')));
      final csv = standingsCsv(c.event!);
      expect(csv, isNot(contains('private')));
      final pdf = await reportPdf(c.event!, ReportKind.packet);
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    },
  );
  test(
    'ASCII rejects unrepresentable names instead of silently corrupting them',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(name: 'José'));
      expect(
        () => crosstable(c.event!, asciiOnly: true),
        throwsA(isA<TournamentException>()),
      );
    },
  );
  test(
    'DBF binary header, descriptors and fields match independently decoded values',
    () {
      final bytes = encodeDbf(
        [const DbfField('NAME', 12), const DbfField('DATE', 8, type: 'D')],
        [
          {'NAME': 'MORGAN', 'DATE': '20260928'},
        ],
        DateTime(2026, 9, 28),
      );
      final header = ByteData.sublistView(bytes);
      expect(bytes[0], 3);
      expect(header.getUint32(4, Endian.little), 1);
      expect(header.getUint16(8, Endian.little), 97);
      expect(header.getUint16(10, Endian.little), 21);
      expect(bytes[32 + 11], 67);
      expect(ascii.decode(bytes.sublist(98, 110)), 'MORGAN      ');
      expect(ascii.decode(bytes.sublist(110, 118)), '20260928');
      expect(bytes.last, 26);
      expect(
        () => encodeDbf(
          [const DbfField('NAME', 2)],
          [
            {'NAME': 'Long'},
          ],
          DateTime.now(),
        ),
        throwsA(isA<TournamentException>()),
      );
    },
  );
  test(
    'completed quad generates reciprocal chronological 2C records; forfeits omit opponent',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.change(
        'Metadata',
        c.event!.copy(tdId: '12345678', affiliateId: '87654321'),
      );
      for (var i = 0; i < 3; i++) {
        c.post(await c.propose());
        for (final g in c.event!.sections.single.rounds.last.games) {
          c.recordResult(g.id, i == 0 ? Outcome.whiteForfeit : Outcome.draw);
        }
      }
      final files = ratingPackage(
        c.event!,
        const ReportMetadata(
          city: 'Boston',
          state: 'MA',
          zip: '02116',
          ratingSystem: 'R',
        ),
      );
      expect(
        files.keys,
        containsAll(['THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF']),
      );
      expect(
        ascii.decode(
          files['TDEXPORT.DBF']!.where((v) => v >= 32 && v < 127).toList(),
        ),
        contains('X0'),
      );
      c.change('Practice', c.event!.copy(practice: true));
      expect(
        ratingPreflight(c.event!),
        contains('Practice copies cannot produce rating packages.'),
      );
    },
  );
  test('API adapter preserves nulls and rejects identity mismatch', () async {
    final api = RatingsApi(
      MockClient((request) async {
        expect(request.headers['X-Api-Key'], 'secret');
        return http.Response(
          jsonEncode({
            'id': '00123456',
            'firstName': 'Morgan',
            'lastName': 'Lee',
            'stateRep': 'MA',
            'ratings': [
              {'ratingSystem': 'R', 'rating': null},
              {'ratingSystem': 'FUTURE', 'rating': 1800},
            ],
          }),
          200,
        );
      }),
    );
    final member = await api.member('00123456', 'secret');
    expect(member.ratings['R'], isNull);
    expect(member.state, 'MA');
    expect(member.ratings['FUTURE'], 1800);
    final mismatch = RatingsApi(
      MockClient((_) async => http.Response('{"id":"99999999"}', 200)),
    );
    expect(
      () => mismatch.member('00123456', 'secret'),
      throwsA(isA<TournamentException>()),
    );
  });
  for (final status in [401, 404, 429, 503]) {
    test('API failure $status stays distinguishable', () async {
      final api = RatingsApi(
        MockClient((_) async => http.Response('', status)),
      );
      expect(
        () => api.member('00123456', 'key'),
        throwsA(isA<TournamentException>()),
      );
    });
  }
}
