import 'dart:convert';
import 'dart:typed_data';
import '../domain/model.dart';
import '../domain/us_chess.dart';

/// A separate reader checks the bytes, never the writer's field descriptors.
/// Contract transcribed from US Chess 2C, including its September 2025 update.
/// https://secure2.uschess.org/TD_Affil/fileformat.php
const _header = <(String, int)>[
  ('H_FORMAT', 5),
  ('H_PROGRAM', 10),
  ('H_EVENT_ID', 12),
  ('H_NAME', 35),
  ('H_TOT_SECT', 2),
  ('H_BEG_DATE', 8),
  ('H_END_DATE', 8),
  ('H_AFF_ID', 8),
  ('H_CITY', 21),
  ('H_STATE', 2),
  ('H_ZIPCODE', 10),
  ('H_COUNTRY', 21),
  ('H_SENDCROS', 1),
  ('H_CTD_ID', 8),
  ('H_ATD_ID', 8),
  ('H_OTHER_TD', 255),
];
const _section = <(String, int)>[
  ('S_EVENT_ID', 12),
  ('S_SEC_NUM', 2),
  ('S_SEC_NAME', 30),
  ('S_R_SYSTEM', 1),
  ('S_TIMECTL', 40),
  ('S_CTD_ID', 8),
  ('S_ATD_ID', 8),
  ('S_TRN_TYPE', 1),
  ('S_TOT_RNDS', 2),
  ('S_LST_PAIR', 4),
  ('S_BEG_DATE', 8),
  ('S_END_DATE', 8),
  ('S_SCH_LVL', 1),
  ('S_GR_PRIX', 1),
  ('S_GP_PTS', 3),
  ('S_FIDE', 1),
];
const _detail = <(String, int)>[
  ('D_EVENT_ID', 12),
  ('D_SEC_NUM', 2),
  ('D_PAIR_NUM', 4),
  ('D_MEM_ID', 8),
  ('D_NAME', 30),
  ('D_STATE', 2),
  ('D_RATING', 4),
];

void _require(bool value, String issue) {
  if (!value) throw TournamentException('Rating file validation: $issue');
}

List<Map<String, String>> _read(
  Uint8List bytes,
  List<(String, int)> fields,
  String name,
) {
  _require(bytes.length >= 34, '$name is truncated.');
  final view = ByteData.sublistView(bytes);
  final count = view.getUint32(4, Endian.little);
  final header = view.getUint16(8, Endian.little);
  final record = view.getUint16(10, Endian.little);
  _require(
    bytes[0] == 3 && bytes.last == 26,
    '$name has an unsupported DBF header or terminator.',
  );
  _require(
    header == 33 + fields.length * 32 &&
        record == 1 + fields.fold<int>(0, (n, f) => n + f.$2) &&
        bytes.length == header + count * record + 1,
    '$name has inconsistent lengths.',
  );
  _require(bytes[header - 1] == 13, '$name has no descriptor terminator.');
  for (final (i, field) in fields.indexed) {
    final at = 32 + i * 32;
    final actual = ascii.decode(
      bytes.sublist(at, at + 11).takeWhile((n) => n != 0).toList(),
    );
    final type = field.$1.endsWith('_DATE') ? 68 : 67;
    _require(
      actual == field.$1 &&
          bytes[at + 11] == type &&
          bytes[at + 16] == field.$2 &&
          bytes[at + 17] == 0,
      '$name field ${field.$1} does not match the published 2C layout.',
    );
  }
  final rows = <Map<String, String>>[];
  for (var i = 0; i < count; i++) {
    var at = header + i * record;
    _require(bytes[at++] == 32, '$name contains a deleted record.');
    final row = <String, String>{};
    for (final (field, width) in fields) {
      final data = bytes.sublist(at, at + width);
      _require(
        data.every((b) => b >= 32 && b <= 126),
        '$name $field is not printable ASCII.',
      );
      final text = ascii.decode(data);
      row[field] = text.trimRight();
      if (field.endsWith('_DATE')) {
        _require(
          RegExp(r'^\d{8}$').hasMatch(text),
          '$field has an invalid date.',
        );
        _require(
          isEventDate(
            '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}',
          ),
          '$field is not a calendar date.',
        );
      } else {
        _require(
          text == text.trim().padRight(width),
          '$field must be left-justified and space-filled.',
        );
      }
      at += width;
    }
    rows.add(row);
  }
  return rows;
}

/// Exact source-to-output comparison also catches reciprocal but wrong results.
/// Passing this check says nothing about membership/TD authority or MUIR acceptance.
Json validateRatingFiles(Event e, Map<String, Uint8List> files) {
  const names = {'THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF'};
  _require(
    files.length == 3 && files.keys.toSet().containsAll(names),
    'Provide all three DBF files together.',
  );
  final sections = e.sections.where((s) => s.players.isNotEmpty).toList();
  _require(sections.isNotEmpty, 'No reportable sections.');
  final rounds = sections.first.rounds.length;
  final headers = _read(files['THEXPORT.DBF']!, _header, 'THEXPORT.DBF');
  final sectionRows = _read(files['TSEXPORT.DBF']!, _section, 'TSEXPORT.DBF');
  final details = _read(files['TDEXPORT.DBF']!, [
    ..._detail,
    for (var n = 1; n <= rounds; n++)
      ('D_RND${n.toString().padLeft(2, '0')}', 7),
  ], 'TDEXPORT.DBF');
  _require(
    headers.length == 1 &&
        sectionRows.length == sections.length &&
        details.length == sections.fold<int>(0, (n, s) => n + s.players.length),
    'Record counts do not match the event.',
  );
  void equals(Map<String, String> row, String field, String expected) =>
      _require(row[field] == expected, '$field differs from the source event.');
  final header = headers.single;
  final begin = e.date.replaceAll('-', ''),
      end = e.lastDate.replaceAll('-', '');
  for (final field in {
    'H_FORMAT': '2C',
    'H_EVENT_ID': 'MEOW',
    'H_NAME': reportText(e.name)!,
    'H_TOT_SECT': '${sections.length}',
    'H_BEG_DATE': begin,
    'H_END_DATE': end,
    'H_AFF_ID': e.affiliateId,
    'H_CITY': reportText(e.city)!,
    'H_STATE': e.state,
    'H_ZIPCODE': e.zip,
    'H_COUNTRY': 'USA',
    'H_SENDCROS': 'N',
    'H_CTD_ID': e.tdId,
    'H_ATD_ID': '',
    'H_OTHER_TD': '',
  }.entries) {
    equals(header, field.key, field.value);
  }
  _require(
    header['H_PROGRAM']!.startsWith('MEOW '),
    'Missing program identity.',
  );
  final tc = TimeControl.parse(e.timeControl);
  var offset = 0, played = 0, unplayed = 0;
  for (final (i, s) in sections.indexed) {
    final numbers = {for (final (j, id) in s.players.indexed) id: '${j + 1}'};
    final sr = sectionRows[i];
    for (final field in {
      'S_EVENT_ID': 'MEOW',
      'S_SEC_NUM': '${i + 1}',
      'S_SEC_NAME': reportText(s.name)!,
      'S_R_SYSTEM': tc.category!.code!,
      'S_TIMECTL': tc.reportText,
      'S_CTD_ID': e.tdId,
      'S_ATD_ID': '',
      'S_TRN_TYPE': 'S',
      'S_TOT_RNDS': '${s.rounds.length}',
      'S_LST_PAIR': '${s.players.length}',
      'S_BEG_DATE': begin,
      'S_END_DATE': end,
      'S_SCH_LVL': e.level,
      'S_GR_PRIX': 'N',
      'S_GP_PTS': '0',
      'S_FIDE': 'N',
    }.entries) {
      equals(sr, field.key, field.value);
    }
    for (final id in s.players) {
      final player = e.player(id), row = details[offset++];
      for (final field in {
        'D_EVENT_ID': 'MEOW',
        'D_SEC_NUM': '${i + 1}',
        'D_PAIR_NUM': numbers[id]!,
        'D_MEM_ID': player.memberId,
        'D_NAME': playerReportName(player)!,
        'D_STATE': player.state,
        'D_RATING': '${player.rating}',
      }.entries) {
        equals(row, field.key, field.value);
      }
      for (final r in s.rounds) {
        final g = r.games
            .where((g) => g.white == id || g.black == id)
            .firstOrNull;
        String expected;
        if (g == null) {
          final award = r.byes.where((b) => b.player == id).firstOrNull;
          _require(
            award != null,
            'Missing result/bye for ${player.name}, round ${r.number}.',
          );
          expected = switch (award!.points) {
            2 => 'B0',
            1 => 'H0',
            0 => 'U0',
            _ => throw const TournamentException(
              'Unsupported bye value for US Chess export.',
            ),
          };
          unplayed++;
        } else {
          final white = g.white == id;
          final codes = switch (g.outcome) {
            Outcome.whiteWin => ('W', 'L'),
            Outcome.blackWin => ('L', 'W'),
            Outcome.draw => ('D', 'D'),
            Outcome.whiteForfeit => ('X', 'F'),
            Outcome.blackForfeit => ('F', 'X'),
            Outcome.doubleForfeit => ('F', 'F'),
            _ => throw const TournamentException(
              'Unresolved game in rating files.',
            ),
          };
          final code = white ? codes.$1 : codes.$2;
          if (['W', 'D', 'L'].contains(code)) {
            final opponent = numbers[white ? g.black : g.white];
            _require(
              opponent != null,
              'Opponent is outside the reported section.',
            );
            expected = '$code$opponent${white ? 'W' : 'B'}';
            played++;
          } else {
            expected = '${code}0';
            unplayed++;
          }
        }
        equals(row, 'D_RND${r.number.toString().padLeft(2, '0')}', expected);
      }
    }
  }
  return {
    'status': 'passed',
    'scope': 'Offline format and source-event checks only',
    'portalAcceptance': 'not tested',
    'specification': 'https://secure2.uschess.org/TD_Affil/fileformat.php',
    'sections': sections.length,
    'entries': details.length,
    'rounds': rounds,
    'playedGames': played ~/ 2,
    'unplayedPlayerRounds': unplayed,
    'checks': [
      '2C field names/types/widths',
      'DBF byte lengths and padding',
      'Record counts and event/section/player references',
      'Every result and color against the source event',
    ],
  };
}
