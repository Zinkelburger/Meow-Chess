import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/web_roster.dart';

List<int> utf16le(String text) => [
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

String page(String name) =>
    '<table><tr><th>Name</th><th>Rating</th><th>USCF ID</th></tr>'
    '<tr><td>$name</td><td>1500</td><td>00123456</td></tr></table>';

void main() {
  group('decodeRosterText', () {
    test('plain ASCII and UTF-8 decode unchanged', () {
      expect(decodeRosterText(ascii.encode('Name\nAda')), 'Name\nAda');
      expect(decodeRosterText(utf8.encode('José Müller')), 'José Müller');
      expect(decodeRosterText([]), '');
    });

    test('a UTF-8 byte-order mark is removed', () {
      expect(
        decodeRosterText([0xEF, 0xBB, 0xBF, ...utf8.encode('Name,ID\nJosé')]),
        'Name,ID\nJosé',
      );
    });

    test('Excel "Unicode Text" (UTF-16 with a byte-order mark) decodes', () {
      const text = 'Name\tRating\r\nJosé Ñúñez\t1500\r\n李 Wei\t0';
      expect(decodeRosterText([0xFF, 0xFE, ...utf16le(text)]), text);
      final bigEndian = [
        0xFE,
        0xFF,
        for (final unit in text.codeUnits) ...[unit >> 8, unit & 0xFF],
      ];
      expect(decodeRosterText(bigEndian), text);
    });

    test('Windows-1252 from Excel "CSV" on Windows decodes', () {
      // "José" with é as 0xE9, plus the curly quote and euro sign that only
      // Windows-1252 places in 0x80-0x9F.
      final bytes = [
        ...ascii.encode('Name\nJos'),
        0xE9,
        ...ascii.encode(' O'),
        0x92,
        ...ascii.encode('Brien '),
        0x80,
        0x9F,
      ];
      expect(decodeRosterText(bytes), 'Name\nJosé O’Brien €Ÿ');
    });

    test('invalid UTF-8 falls back instead of failing', () {
      expect(decodeRosterText([0x41, 0xFF, 0xC3]), 'AÿÃ');
      // Unassigned Windows-1252 bytes keep their Latin-1 code points.
      expect(decodeRosterText([0x81, 0x8D]), '\u0081\u008D');
    });

    test('a declared character set is honored; a byte-order mark wins', () {
      expect(decodeRosterText([0xE9], charset: 'ISO-8859-1'), 'é');
      expect(decodeRosterText([0x93, 0x94], charset: '"windows-1252"'), '“”');
      expect(decodeRosterText(utf16le('Zoë'), charset: 'UTF-16LE'), 'Zoë');
      expect(
        decodeRosterText([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode('é'),
        ], charset: 'latin1'),
        'é',
      );
      expect(decodeRosterText(utf8.encode('é'), charset: 'unknown'), 'é');
    });
  });

  group('one-column "Last, First" lists', () {
    const list = 'Smith, John\nO’Brien, Mary Ann\nvan der Berg, Pieter';
    test('are not split on the comma', () {
      expect(detectSeparator(list), isNull);
      final rows = parseRoster(list);
      expect(rows.map((r) => r.error), everyElement(isNull));
      expect(rows.map((r) => r.player!.name), [
        'Smith, John',
        'O’Brien, Mary Ann',
        'van der Berg, Pieter',
      ]);
      expect(detectSeparator('Name\n$list'), isNull);
      expect(parseRoster('Name\n$list').first.player!.name, 'Smith, John');
    });

    test('real two-column files keep comma detection', () {
      for (final source in [
        'Smith,John\nLee,Ada',
        'Last, First\nSmith, John',
        'Smith, 12345678\nLee, 00123456',
        'Ada Lee, MA\nBo Chen, NH',
        'Smith, John, 1500\nLee, Ada, 1400',
        'Smith, John\nLee, Ada\nChen, 1500',
      ]) {
        expect(detectSeparator(source), ',', reason: source);
      }
      expect(
        parseRoster('Smith, 12345678').single.player!.memberId,
        '12345678',
      );
    });
  });

  group('reported line numbers are file lines', () {
    test('a quoted cell with a line break shifts the following rows', () {
      const source =
          'Name,ID,Rating\n'
          '"Multi\nLine",12345678,1500\n'
          'Bad,abc,1500\n'
          '\n'
          'Worse,12345679,nope';
      final split = RosterTable.split(source, separators: {','});
      expect(split.lines, [1, 2, 4, 5, 6]);
      final rows = split.interpret(
        hasHeader: true,
        columns: split.suggestColumns(true),
      );
      expect(rows.map((r) => r.line), [2, 4, 6]);
      expect(rows[1].error, contains('eight digits'));
      expect(rows[2].error, contains('Rating'));
      expect(parseRoster(source).map((r) => r.line), [2, 4, 6]);
    });

    test('CRLF and CR line endings inside and outside quotes', () {
      final split = RosterTable.split(
        'Name\r\n"A\r\nB"\r\nC\rD',
        separators: {','},
      );
      expect(split.rows, [
        ['Name'],
        ['A\r\nB'],
        ['C'],
        ['D'],
      ]);
      expect(split.lines, [1, 2, 4, 5]);
      expect(
        parseRoster(
          'Name,ID\r\n"Lee,\r\nMorgan",123\r\nOk,00123456',
        ).map((r) => (r.line, r.error != null)),
        [(2, true), (4, false)],
      );
    });
  });

  group('RosterTable.split and detectSeparator', () {
    test('doubled quotes, separators and line breaks inside quotes', () {
      expect(
        RosterTable.split(
          'Name,Note\n"Lee, ""Morgan""","a\nb"\n',
          separators: {','},
        ).rows,
        [
          ['Name', 'Note'],
          ['Lee, "Morgan"', 'a\nb'],
        ],
      );
    });

    test('byte-order marks are ignored, including stray ones', () {
      final table = RosterTable.split(
        '﻿Name,ID\nAda,00123456\n﻿Name,ID\nBo,00123457',
        separators: {','},
      );
      expect(table.rows.first, ['Name', 'ID']);
      expect(table.rows[2], ['Name', 'ID']);
      expect(detectSeparator('﻿Name;ID\n﻿Ada;00123456'), ';');
    });

    test('pipe, semicolon and tab detection', () {
      expect(detectSeparator('Name|ID|Rating\nAda|00123456|1500'), '|');
      expect(
        detectSeparator('Name;ID;Rating\n"Lee, Morgan";00123456;1500'),
        ';',
      );
      expect(detectSeparator('Name\tID\nLee, Ada\t00123456'), '\t');
      expect(
        RosterTable.split('Name|ID\nAda|00123456', separators: {'|'}).rows.last,
        ['Ada', '00123456'],
      );
    });

    test('empty and header-only files', () {
      for (final source in ['', '﻿', '\n\n']) {
        expect(detectSeparator(source), isNull);
        final table = RosterTable.split(source, separators: {','});
        expect(
          table.interpret(hasHeader: true, columns: {RosterField.name: 0}),
          isEmpty,
        );
      }
      final header = RosterTable.split('Name,ID,Rating\r\n', separators: {','});
      expect(header.rows, [
        ['Name', 'ID', 'Rating'],
      ]);
      expect(header.suggestsHeader, true);
      expect(
        header.interpret(hasHeader: true, columns: header.headerColumns),
        isEmpty,
      );
      expect(detectSeparator('Name,ID,Rating'), ',');
    });
  });

  group('web entry lists', () {
    test('a line break between names inside a cell reads as a space', () {
      final rows = parseWebRoster(page('John<br>Smith'));
      expect(rows.single.player!.name, 'John Smith');
      expect(
        parseWebRoster(
          page('<div>Ada</div><div>Lee</div>'),
        ).single.player!.name,
        'Ada Lee',
      );
      expect(
        parseWebRoster(page('Lee; Morgan')).single.player!.name,
        'Lee; Morgan',
      );
    });

    Future<String> fetchName(
      List<int> body, {
      Map<String, String> headers = const {},
    }) async {
      final client = MockClient(
        (request) async => http.Response.bytes(body, 200, headers: headers),
      );
      addTearDown(client.close);
      final rows = await WebRoster(
        client,
      ).fetch('https://another-club.example/entries');
      return rows.single.player!.name;
    }

    test('the declared character set decides how the page is read', () async {
      expect(
        await fetchName(
          latin1.encode(page('José')),
          headers: {'content-type': 'text/html; charset=ISO-8859-1'},
        ),
        'José',
      );
      expect(
        await fetchName(
          latin1.encode('<meta charset="windows-1252">${page('José')}'),
        ),
        'José',
      );
      expect(
        await fetchName(
          latin1.encode(
            '<meta http-equiv="Content-Type" content="text/html; '
            'charset=iso-8859-1">${page('Zoë')}',
          ),
        ),
        'Zoë',
      );
      expect(
        await fetchName(
          utf8.encode(page('José')),
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
        'José',
      );
      // A page that is not the UTF-8 it claims still loads.
      expect(
        await fetchName(
          latin1.encode(page('José')),
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
        'José',
      );
    });

    test('network failures explain that the site could not be reached', () {
      for (final failure in <Object>[
        TimeoutException('slow'),
        const SocketException('Failed host lookup'),
        http.ClientException('Connection closed'),
        const HandshakeException('bad certificate'),
      ]) {
        final client = MockClient((request) async => throw failure);
        addTearDown(client.close);
        expect(
          WebRoster(client).fetch('https://another-club.example/entries'),
          throwsA(
            isA<TournamentException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Could not reach another-club.example'),
                contains('Your roster is unchanged'),
              ),
            ),
          ),
          reason: '$failure',
        );
      }
    });

    test('a stalled body is reported as unreachable', () async {
      final client = MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream<List<int>>.error(TimeoutException('stalled')),
          200,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        WebRoster(client).fetch('https://another-club.example/entries'),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach another-club.example'),
          ),
        ),
      );
    });
  });
}
