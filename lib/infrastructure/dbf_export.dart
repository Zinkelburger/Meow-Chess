import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../domain/model.dart';

class DbfField {
  const DbfField(this.name, this.width, {this.type = 'C'});
  final String name, type;
  final int width;
}

/// dBASE III, strict ASCII, left-justified character fields per 2C's 2025 correction.
Uint8List encodeDbf(
  List<DbfField> fields,
  List<Map<String, String>> records,
  DateTime date,
) {
  final header = 32 + fields.length * 32 + 1,
      record = 1 + fields.fold<int>(0, (n, f) => n + f.width);
  if (header > 65535 || record > 65535) {
    throw const TournamentException('DBF field limits exceeded.');
  }
  final bytes = Uint8List(header + records.length * record + 1);
  final view = ByteData.sublistView(bytes);
  bytes[0] = 3;
  bytes[1] = date.year - 1900;
  bytes[2] = date.month;
  bytes[3] = date.day;
  view.setUint32(4, records.length, Endian.little);
  view.setUint16(8, header, Endian.little);
  view.setUint16(10, record, Endian.little);
  for (final (i, f) in fields.indexed) {
    if (f.name.length > 10 || f.width < 1 || f.width > 255) {
      throw const TournamentException('Invalid DBF schema.');
    }
    final at = 32 + i * 32;
    bytes.setRange(at, at + f.name.length, ascii.encode(f.name));
    bytes[at + 11] = f.type.codeUnitAt(0);
    bytes[at + 16] = f.width;
  }
  bytes[header - 1] = 13;
  for (final (i, row) in records.indexed) {
    var offset = header + i * record;
    bytes[offset++] = 32;
    for (final f in fields) {
      final value = row[f.name] ?? '';
      if (value.length > f.width ||
          value.codeUnits.any((c) => c < 32 || c > 126)) {
        throw TournamentException(
          '${f.name}: "$value" needs an ASCII export alias within ${f.width} characters. Nothing was truncated.',
        );
      }
      bytes.setRange(
        offset,
        offset + f.width,
        ascii.encode(value.padRight(f.width)),
      );
      offset += f.width;
    }
  }
  bytes.last = 26;
  return bytes;
}

class ReportMetadata {
  const ReportMetadata({
    required this.city,
    required this.state,
    required this.zip,
    required this.ratingSystem,
  });
  final String city, state, zip, ratingSystem;
}

List<String> ratingPreflight(Event e) {
  return [
    if (e.practice) 'Practice copies cannot produce rating packages.',
    if (e.sections.isEmpty) 'Create sections first.',
    if (e.sections.any((s) => s.players.isNotEmpty && !s.finished))
      'Complete all scheduled rounds and results.',
    if (!RegExp(r'^\d{8}$').hasMatch(e.tdId))
      'Enter the chief TD’s eight-digit ID in event settings.',
    if (!RegExp(r'^\d{8}$').hasMatch(e.affiliateId))
      'Enter the affiliate’s eight-digit ID in event settings.',
    for (final player in e.players.where(
      (p) => e.sectionOf(p.id) != null && p.memberId.isEmpty,
    ))
      '${player.name}: US Chess ID missing.',
    if (e.sections.any((s) => s.doubleGames))
      'Double-game report mapping awaits accepted reference fixtures.',
    if (e.transitions.any((t) => (t['effectiveRound'] as int) > 1))
      'Post-play transfers require an externally validated reporting mapping.',
    if (e.sections.map((s) => s.rounds.length).toSet().length > 1)
      'Mixed round-count encoding awaits accepted reference fixtures.',
    if (e.sections.length > 99 ||
        e.sections.any((s) => s.rounds.length > 32 || s.players.length > 9999))
      'Event exceeds the supported 2C field limits.',
  ];
}

Map<String, Uint8List> ratingPackage(Event e, ReportMetadata metadata) {
  final issues = ratingPreflight(e);
  if (issues.isNotEmpty) throw TournamentException(issues.join('\n'));
  if (!['R', 'D', 'Q'].contains(metadata.ratingSystem) ||
      metadata.city.trim().isEmpty ||
      !RegExp(r'^[A-Z]{2}$').hasMatch(metadata.state) ||
      !RegExp(r'^\d{5}(-\d{4})?$').hasMatch(metadata.zip)) {
    throw const TournamentException(
      'Provide city, two-letter state, ZIP and a reviewed R/D/Q rating category. Blitz and online mappings are unavailable.',
    );
  }
  final date = DateTime.parse(e.date), dateCode = e.date.replaceAll('-', '');
  final sections = e.sections.where((s) => s.players.isNotEmpty).toList();
  const headerFields = [
    DbfField('H_FORMAT', 5),
    DbfField('H_PROGRAM', 10),
    DbfField('H_EVENT_ID', 12),
    DbfField('H_NAME', 35),
    DbfField('H_TOT_SECT', 2),
    DbfField('H_BEG_DATE', 8, type: 'D'),
    DbfField('H_END_DATE', 8, type: 'D'),
    DbfField('H_AFF_ID', 8),
    DbfField('H_CITY', 21),
    DbfField('H_STATE', 2),
    DbfField('H_ZIPCODE', 10),
    DbfField('H_COUNTRY', 21),
    DbfField('H_SENDCROS', 1),
    DbfField('H_CTD_ID', 8),
    DbfField('H_ATD_ID', 8),
    DbfField('H_OTHER_TD', 255),
  ];
  const sectionFields = [
    DbfField('S_EVENT_ID', 12),
    DbfField('S_SEC_NUM', 2),
    DbfField('S_SEC_NAME', 30),
    DbfField('S_R_SYSTEM', 1),
    DbfField('S_TIMECTL', 40),
    DbfField('S_CTD_ID', 8),
    DbfField('S_ATD_ID', 8),
    DbfField('S_TRN_TYPE', 1),
    DbfField('S_TOT_RNDS', 2),
    DbfField('S_LST_PAIR', 4),
    DbfField('S_BEG_DATE', 8, type: 'D'),
    DbfField('S_END_DATE', 8, type: 'D'),
    DbfField('S_SCH_LVL', 1),
    DbfField('S_GR_PRIX', 1),
    DbfField('S_GP_PTS', 3),
    DbfField('S_FIDE', 1),
  ];
  final rounds = sections.first.rounds.length;
  final detailFields = [
    const DbfField('D_EVENT_ID', 12),
    const DbfField('D_SEC_NUM', 2),
    const DbfField('D_PAIR_NUM', 4),
    const DbfField('D_MEM_ID', 8),
    const DbfField('D_NAME', 30),
    const DbfField('D_STATE', 2),
    const DbfField('D_RATING', 4),
    for (var i = 1; i <= rounds; i++)
      DbfField('D_RND${i.toString().padLeft(2, '0')}', 7),
  ];
  final sectionRows = <Map<String, String>>[],
      detailRows = <Map<String, String>>[];
  for (final (i, s) in sections.indexed) {
    final number = '${i + 1}';
    final pairs = {for (final (j, id) in s.players.indexed) id: j + 1};
    sectionRows.add({
      'S_EVENT_ID': 'MEOW',
      'S_SEC_NUM': number,
      'S_SEC_NAME': s.name,
      'S_R_SYSTEM': metadata.ratingSystem,
      'S_TIMECTL': e.timeControl,
      'S_CTD_ID': e.tdId,
      'S_TRN_TYPE': 'S',
      'S_TOT_RNDS': '$rounds',
      'S_LST_PAIR': '${s.players.length}',
      'S_BEG_DATE': dateCode,
      'S_END_DATE': dateCode,
      'S_SCH_LVL': 'N',
      'S_GR_PRIX': 'N',
      'S_GP_PTS': '0',
      'S_FIDE': 'N',
    });
    for (final id in s.players) {
      final player = e.player(id);
      final row = {
        'D_EVENT_ID': 'MEOW',
        'D_SEC_NUM': number,
        'D_PAIR_NUM': '${pairs[id]}',
        'D_MEM_ID': player.memberId,
        'D_NAME': player.name,
        'D_STATE': '',
        'D_RATING': '${player.rating}',
      };
      for (final r in s.rounds) {
        final game = r.games
            .where((g) => g.white == id || g.black == id)
            .firstOrNull;
        String code;
        if (game == null) {
          final bye = r.byes.where((b) => b.player == id).firstOrNull;
          code =
              '${bye?.points == 2
                  ? 'B'
                  : bye?.points == 1
                  ? 'H'
                  : 'U'}0';
        } else {
          final white = game.white == id,
              points = game.white == id
                  ? game.outcome.whiteScore
                  : game.outcome.blackScore;
          code = game.outcome.played
              ? '${points == 2
                    ? 'W'
                    : points == 1
                    ? 'D'
                    : 'L'}${pairs[white ? game.black : game.white]}${white ? 'W' : 'B'}'
              : '${points == 2 ? 'X' : 'F'}0';
        }
        row['D_RND${r.number.toString().padLeft(2, '0')}'] = code;
      }
      detailRows.add(row);
    }
  }
  return {
    'THEXPORT.DBF': encodeDbf(headerFields, [
      {
        'H_FORMAT': '2C',
        'H_PROGRAM': 'MEOW 0.1',
        'H_EVENT_ID': 'MEOW',
        'H_NAME': e.name,
        'H_TOT_SECT': '${sections.length}',
        'H_BEG_DATE': dateCode,
        'H_END_DATE': dateCode,
        'H_AFF_ID': e.affiliateId,
        'H_CITY': metadata.city,
        'H_STATE': metadata.state,
        'H_ZIPCODE': metadata.zip,
        'H_COUNTRY': 'USA',
        'H_SENDCROS': 'N',
        'H_CTD_ID': e.tdId,
      },
    ], date),
    'TSEXPORT.DBF': encodeDbf(sectionFields, sectionRows, date),
    'TDEXPORT.DBF': encodeDbf(detailFields, detailRows, date),
  };
}

Future<String> writeRatingPackage(
  Event e,
  ReportMetadata metadata,
  String parent,
) async {
  final files = ratingPackage(e, metadata);
  final name = 'meow-r${e.revision}-${DateTime.now().microsecondsSinceEpoch}';
  final staging = Directory(p.join(parent, '.$name.partial'));
  await staging.create(recursive: true);
  try {
    for (final entry in files.entries) {
      await File(
        p.join(staging.path, entry.key),
      ).writeAsBytes(entry.value, flush: true);
    }
    await File(p.join(staging.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'eventId': e.id,
        'revision': e.revision,
        'schema': '2C-2025-character-correction',
        'status':
            'UNVERIFIED — TD/provider validation required before submission',
        'files': files.map((k, v) => MapEntry(k, v.length)),
      }),
      flush: true,
    );
    final target = p.join(parent, name);
    await staging.rename(target);
    return target;
  } catch (_) {
    if (await staging.exists()) await staging.delete(recursive: true);
    rethrow;
  }
}
