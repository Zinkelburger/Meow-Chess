import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../domain/model.dart';
import '../domain/us_chess.dart';

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
  if (date.year < 1900 || date.year > 2155) {
    throw const TournamentException('DBF dates must fall in 1900–2155.');
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

/// Sent as `H_PROGRAM` (at most ten characters). A test keeps it equal to the
/// version in pubspec.yaml.
const appVersion = '1.1.0';

/// Sections that appear in the report: every section with entrants.
List<Section> reportedSections(Event e) =>
    e.sections.where((s) => s.players.isNotEmpty).toList();

String _list(Iterable<String> names) {
  final all = names.toList();
  return all.length <= 6
      ? all.join(', ')
      : '${all.take(5).join(', ')} and ${all.length - 5} more';
}

/// Why [value] cannot go in a [width]-character text field, or null.
String? _textProblem(String value, int width) {
  final text = reportText(value);
  if (text == null) return 'uses characters with no plain-letter spelling';
  if (text.isEmpty) return 'is empty';
  final bad = unsafeCharacter(text);
  if (bad != null) return 'contains $bad, which the report leaves out';
  if (text.length > width) {
    return 'is ${text.length} characters; US Chess allows $width';
  }
  return null;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Everything that would make the rating report wrong, unreadable, or likely
/// to be refused. Each entry says what to change. Empty means the files can be
/// created. Field rules follow the 2C format (research/local/uscf-fileformat.txt)
/// and rating categories follow rule 5C (research/local/uscf-rules-2026.txt).
enum ReportDestination { event, report, player, section, results }

class ReportRepair {
  const ReportRepair(this.label, this.destination, {this.id, this.field});
  final String label;
  final ReportDestination destination;
  final String? id, field;
}

class ReportIssue {
  const ReportIssue(this.message, this.repairs);
  final String message;
  final List<ReportRepair> repairs;
}

List<String> ratingPreflight(Event e, {DateTime? today}) =>
    ratingIssues(e, today: today).map((issue) => issue.message).toList();

List<ReportIssue> ratingIssues(Event e, {DateTime? today}) {
  final issues = <ReportIssue>[];
  void add(String message, {List<ReportRepair> repairs = const []}) =>
      issues.add(ReportIssue(message, repairs));
  ReportRepair event(String field) =>
      ReportRepair('Edit event details', ReportDestination.event, field: field);
  ReportRepair report(String field) => ReportRepair(
    'Edit report details',
    ReportDestination.report,
    field: field,
  );
  ReportRepair player(Player p, String field) => ReportRepair(
    'Edit ${p.name}',
    ReportDestination.player,
    id: p.id,
    field: field,
  );
  void check(String? problem, String message, {ReportRepair? repair}) {
    if (problem != null) {
      add(
        message.replaceFirst('{}', problem),
        repairs: repair == null ? [] : [repair],
      );
    }
  }

  final sections = reportedSections(e);
  if (e.practice) add('Practice copies cannot produce rating reports.');
  if (sections.isEmpty) add('Create sections and add players first.');
  if (sections.any((s) => !s.finished)) {
    add(
      'Complete all scheduled rounds and results.',
      repairs: [
        for (final s in sections.where((s) => !s.finished))
          ReportRepair(
            'Open ${s.name} results',
            ReportDestination.results,
            id: s.id,
          ),
      ],
    );
  }

  // Event details.
  check(
    _textProblem(e.name, 35),
    'Event name {}. Change it in Event details.',
    repair: event('name'),
  );
  if (!isMemberId(e.tdId)) {
    add(
      'Enter the chief TD\'s eight-digit US Chess ID in Event details.',
      repairs: [event('td')],
    );
  }
  if (!isAffiliateId(e.affiliateId)) {
    add(
      'Enter the affiliate ID in Event details: the letter A and seven digits, like A6012345.',
      repairs: [event('affiliate')],
    );
  }
  final now = _day(today ?? DateTime.now());
  if (!isEventDate(e.date) ||
      (e.endDate.isNotEmpty &&
          (!isEventDate(e.endDate) || e.endDate.compareTo(e.date) < 0))) {
    add(
      'Check the event dates in Event details: the last day cannot come before the first.',
      repairs: [event('date')],
    );
  } else if (e.lastDate.compareTo(now) > 0) {
    add(
      'The event ends after today (${e.lastDate}). Check the dates in Event details.',
      repairs: [event('date')],
    );
  } else if (e.date.compareTo('2000-01-01') < 0) {
    add(
      'Check the event date in Event details (${e.date}).',
      repairs: [event('date')],
    );
  }
  try {
    final tc = TimeControl.parse(e.timeControl);
    final category = tc.category;
    if (category == null) {
      add(
        'Time control ${e.timeControl} is not ratable: rule 5C needs at least five minutes in total, and five in the first control above G/10.',
        repairs: [event('time')],
      );
    } else if (category.code == null) {
      add(
        'Blitz events cannot be reported in this file format yet. Report them on the US Chess website.',
      );
    }
    check(
      tc.reportText.length > 40 ? 'is too long for the report' : null,
      'Time control {}. Simplify it in Event details.',
      repair: event('time'),
    );
  } on TournamentException catch (error) {
    add(
      '${error.message} Change it in Event details.',
      repairs: [event('time')],
    );
  }

  // Report details.
  check(
    _textProblem(e.city, 21),
    'City {}. Enter it under Report details.',
    repair: report('city'),
  );
  if (!usStates.contains(e.state)) {
    add(
      'Enter the two-letter state where the event was held under Report details.',
      repairs: [report('state')],
    );
  }
  if (!isZipCode(e.zip)) {
    add(
      'Enter the ZIP code (12345 or 12345-6789) under Report details.',
      repairs: [report('zip')],
    );
  }
  if (!sectionLevels.containsKey(e.level)) {
    add(
      'Choose the event type under Report details.',
      repairs: [report('level')],
    );
  }

  // Sections.
  if (sections.length > 99) {
    add('US Chess reports allow at most 99 sections.');
  }
  if (sections.map((s) => s.rounds.length).toSet().length > 1) {
    add(
      'Sections with different numbers of rounds cannot be reported together yet.',
    );
  }
  if (sections.any((s) => s.doubleGames)) {
    add('Double-game sections cannot be reported yet.');
  }
  if (e.transitions.any((t) => (t['effectiveRound'] as int) > 1)) {
    add(
      'Players moved between sections after play started; this cannot be reported yet.',
    );
  }
  for (final s in sections) {
    check(
      _textProblem(s.name, 30),
      'Section name "${s.name}" {}. Rename the section.',
      repair: ReportRepair(
        'Edit ${s.name}',
        ReportDestination.section,
        id: s.id,
        field: 'name',
      ),
    );
    final members = s.players.toSet();
    if (members.length < 2) {
      add('Section ${s.name} needs at least two players to be rated.');
    }
    if (s.rounds.length > 32 || members.length > 9999) {
      add('Section ${s.name} exceeds 32 rounds or 9999 players.');
    }
    if (s.finished &&
        !s.rounds.any((r) => r.games.any((g) => g.outcome.played))) {
      add('Section ${s.name} has no played games to rate.');
    }
    for (final r in s.rounds) {
      if (r.games.any(
            (g) => !members.contains(g.white) || !members.contains(g.black),
          ) ||
          r.byes.any((b) => !members.contains(b.player))) {
        add(
          'Section ${s.name}, round ${r.number} includes a player who is no longer in the section.',
        );
      }
    }
  }

  // Players.
  final entrants = [
    for (final s in sections)
      for (final id in s.players) (s, e.player(id)),
  ];
  final noId = [
    for (final (_, p) in entrants)
      if (!isMemberId(p.memberId)) p,
  ];
  if (noId.isNotEmpty) {
    add(
      'US Chess ID missing or invalid for ${_list(noId.map((p) => p.name))}. Every player needs one to be rated.',
      repairs: [for (final p in noId) player(p, 'memberId')],
    );
  }
  final byId = <String, List<(Section, Player)>>{};
  for (final entry in entrants) {
    if (isMemberId(entry.$2.memberId)) {
      byId.putIfAbsent(entry.$2.memberId, () => []).add(entry);
    }
  }
  for (final MapEntry(key: id, value: same) in byId.entries) {
    final people = same.map((x) => x.$2.personId ?? x.$2.id).toSet();
    final sectionIds = same.map((x) => x.$1.id).toSet();
    if (people.length > 1 || sectionIds.length < same.length) {
      add(
        'US Chess ID $id is entered for ${_list(same.map((x) => x.$2.name))}.',
        repairs: [for (final (_, p) in same) player(p, 'memberId')],
      );
    }
  }
  final noState = [
    for (final (_, p) in entrants)
      if (p.state.isEmpty) p,
  ];
  if (noState.isNotEmpty) {
    add(
      'State missing for ${_list(noState.map((p) => p.name))}. Look them up by US Chess ID, enter it in the player panel, or use the button below.',
      repairs: [for (final p in noState) player(p, 'state')],
    );
  }
  for (final (_, p) in entrants) {
    check(
      reportNameProblem(playerReportName(p)),
      '${p.name}: name {}. Set "Name on rating report" in the player panel.',
      repair: player(p, 'reportName'),
    );
  }
  return issues;
}

Map<String, Uint8List> ratingPackage(Event e, {DateTime? today}) {
  final issues = ratingPreflight(e, today: today);
  if (issues.isNotEmpty) throw TournamentException(issues.join('\n'));
  final tc = TimeControl.parse(e.timeControl);
  final system = tc.category!.code!;
  final begin = e.date.replaceAll('-', ''),
      end = e.lastDate.replaceAll('-', '');
  final sections = reportedSections(e);
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
    // 2C lists 255; dBase III character fields hold at most 254 bytes, and
    // this optional field is always empty here.
    DbfField('H_OTHER_TD', 254),
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
      'S_SEC_NAME': reportText(s.name)!,
      'S_R_SYSTEM': system,
      'S_TIMECTL': tc.reportText,
      'S_CTD_ID': e.tdId,
      // Quads and round robins are reported round by round, as a Swiss; US
      // Chess documents this as an accepted alternative.
      'S_TRN_TYPE': 'S',
      'S_TOT_RNDS': '$rounds',
      'S_LST_PAIR': '${s.players.length}',
      'S_BEG_DATE': begin,
      'S_END_DATE': end,
      'S_SCH_LVL': e.level,
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
        'D_NAME': playerReportName(player)!,
        'D_STATE': player.state,
        'D_RATING': '${player.rating}',
      };
      for (final r in s.rounds) {
        final game = r.games
            .where((g) => g.white == id || g.black == id)
            .firstOrNull;
        String code;
        if (game == null) {
          final bye = r.byes.where((b) => b.player == id).firstOrNull;
          code = switch (bye?.points) {
            2 => 'B0',
            1 => 'H0',
            _ => 'U0',
          };
        } else {
          final white = game.white == id,
              points = white
                  ? game.outcome.whiteScore
                  : game.outcome.blackScore;
          code = game.outcome.played
              ? '${switch (points) {
                  2 => 'W',
                  1 => 'D',
                  _ => 'L',
                }}${pairs[white ? game.black : game.white]}${white ? 'W' : 'B'}'
              : '${points == 2 ? 'X' : 'F'}0';
        }
        row['D_RND${r.number.toString().padLeft(2, '0')}'] = code;
      }
      detailRows.add(row);
    }
  }
  final date = DateTime.parse(e.lastDate);
  return {
    'THEXPORT.DBF': encodeDbf(headerFields, [
      {
        'H_FORMAT': '2C',
        'H_PROGRAM': 'MEOW $appVersion',
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
      },
    ], date),
    'TSEXPORT.DBF': encodeDbf(sectionFields, sectionRows, date),
    'TDEXPORT.DBF': encodeDbf(detailFields, detailRows, date),
  };
}

Future<String> writeRatingPackage(Event e, String parent) async {
  final files = ratingPackage(e);
  // OS-created unique directories keep simultaneous exports from sharing
  // staging files, even on clocks with coarse timestamp resolution.
  final root = Directory(parent);
  await root.create(recursive: true);
  final staging = await root.createTemp('.meow-r${e.revision}.partial-');
  final suffix = p.basename(staging.path).split('.partial-').last;
  final name = 'meow-r${e.revision}-$suffix';
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
        'ratingSystem': TimeControl.parse(e.timeControl).category!.code,
        'timeControl': TimeControl.parse(e.timeControl).reportText,
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
